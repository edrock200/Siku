# Silo server: Roku needs a different HLS packaging for remuxed streams

Status: open. Siku works around it on the client (see "Siku's workaround" below), but the
fix belongs in silo-server. This note is written so it can be pasted into an issue or PR
against https://github.com/Silo-Server/silo-server.

## Symptom

On a real Roku (tested: Streaming Stick 4K, model 3820X, Roku OS 14), every
`server_remux_hls` plan plays video with **no audio**, whatever the audio codec (copied AC3 and
E-AC3, and server-converted AAC all silent). `server_transcode_hls` plans that encode to H.264
play with sound. Direct play (`original_http`) plays with sound.

## Cause

Roku's streaming specification, "Audio/video chunk format" row for HLS:

> video: TS, CMAF (muxing audio and video not supported for CMAF)
> audio: aac, ac3, eac3

(Roku developer docs, `docs/SPECIFICATIONS/media/index.md` in github.com/rokudev/dev-doc.)
Roku's HLS player accepts fMP4/CMAF segments only when the audio is a **separate rendition**
(`#EXT-X-MEDIA:TYPE=AUDIO` with its own media playlist). Audio muxed into the video's fMP4
segments is ignored, so the picture plays and the sound is missing.

silo-server's HLS remux puts the audio into the video's fMP4 segments:

- `internal/playback/transcode.go` `HLSOutputContainer` / `copyVideoUsesFMP4`: copied video is
  packaged as fMP4 (`-hls_segment_type fmp4`) unless `CopyVideoMPEGTS` is set or the source is
  MPEG-2; audio and video go to the one `stream.m3u8` with `#EXT-X-MAP`.
- `internal/playback/transcode.go` (`-f hls` arguments): no `-var_stream_map`, so there is no
  separate audio rendition and no master playlist with `#EXT-X-MEDIA`.
- `CopyVideoMPEGTS` exists but is only set by the Jellyfin-compatible API
  (`internal/jellycompat/streams.go`, `source.HLSRemuxMPEGTS`), never by protocol v3.

## Prior art

jellyfin-roku's device profile (`source/utils/deviceCapabilities.bs`, `getTranscodingProfiles`)
sends Jellyfin **only** `"Container": "ts", "Protocol": "hls"` transcoding profiles, with H.264
video and AC3 audio (5.1 kept when the output is surround). The Jellyfin server then remuxes and
transcodes for Roku into MPEG-TS segments, which is why Jellyfin plays with sound on the same
hardware. silo-server's Jellyfin-compatible API already honours that (`HLSRemuxMPEGTS`); protocol
v3 only needs the same switch.

## Routes already tried from the client

- `server_remux_hls` (fMP4 segments, audio muxed): video plays, no audio, Video node reports
  zero audio tracks. Same with AC3, E-AC3 and server-converted AAC.
- `server_remux_progressive` (fragmented MP4 over plain HTTP, `-movflags frag_keyframe+delay_moov`):
  the Roku Video node fails immediately (tested 2026-10-07, Streaming Stick 4K, Roku OS 14).
  Roku lists fragmented MP4 only under DASH and HLS.
- `server_transcode_hls` with H.264 (MPEG-TS segments): plays with sound. This is the only
  server-side route a Roku can hear today, at the cost of re-encoding the video.

## Requested change (either is enough; the second is better)

1. **MPEG-TS copy for v3 clients that ask for it.** Add a delivery-scoped client feature (for
   example `hls_mpegts_copy_v1`) that a client lists in
   `client_playback_context.deliveries.hls.features`. When present, the v3 remux route sets
   `TranscodeOpts.CopyVideoMPEGTS = true`, so copied H.264/HEVC video and copied or converted
   AAC/AC3/E-AC3 audio are packaged as MPEG-TS, which Roku plays. Dolby Vision metadata is not
   carried in TS, so a DV8 source would present its HDR10 base layer on this route (the
   `hls_video_sample_entry` logic in `plan_v3.go` `hlsVideoSampleEntryV3` should return "" for it).
2. **Demuxed CMAF.** Package the remux as two renditions (video-only and audio-only fMP4) with a
   master playlist carrying `#EXT-X-STREAM-INF` with `CODECS` (for example
   `"dvh1.08.06,mp4a.40.2"`) and `#EXT-X-MEDIA:TYPE=AUDIO`. This keeps Dolby Vision on Roku and
   matches Apple's HLS authoring rules too. Gate it on a client feature (for example
   `hls_demuxed_cmaf_v1`) so existing hls.js clients are unaffected.

In both cases the `deliveries.hls` capability already carries `features`, so no schema change
is needed; `deliverySupportsFeatureV3` can read the new flag.

## Siku's workaround until then

Siku declares the HLS delivery as "H.264, SDR, AAC/MP3" only (`components/player/PlaybackCaps.brs`,
`PlaybackCaps_delivery`), so the planner never copies HEVC over HLS and any server-side route
becomes an H.264 MPEG-TS transcode with sound; HEVC/DV files still direct-play when the Roku
accepts the container and audio. If a `server_remux_hls` plan still arrives (an H.264 copy),
the player issues one `failure_recovery` replan with classification `unsupported_container` so
the planner skips it. Once the server gains either feature above, Siku will list it under
`deliveries.hls.features` and drop the restriction.
