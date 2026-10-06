' AuthAvatar: circular profile avatar with initial fallback and badges.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.tint = m.top.findNode("tint")
    m.initial = m.top.findNode("initial")
    m.mask = m.top.findNode("mask")
    m.image = m.top.findNode("image")
    m.edge = m.top.findNode("edge")
    m.lock = m.top.findNode("lock")
    m.lockBg = m.top.findNode("lockBg")
    m.lockIcon = m.top.findNode("lockIcon")
    m.kids = m.top.findNode("kids")
    m.kidsBg = m.top.findNode("kidsBg")
    m.kidsLabel = m.top.findNode("kidsLabel")
    m.font = CreateObject("roSGNode", "Font")
    m.font.uri = "pkg:/fonts/Inter-bold.otf"
    m.initial.font = m.font
    m.kidsFont = CreateObject("roSGNode", "Font")
    m.kidsFont.uri = "pkg:/fonts/Inter-black.otf"
    m.kidsLabel.font = m.kidsFont
    m.image.observeField("loadStatus", "onImageStatus")
    layout()
end sub

' Warm tile colors from Android ProfileTilePalette, picked by DJB2 of the id.
' DJB2 is computed mod 8 as it goes, which matches the unsigned 64-bit hash mod 8.
function avatarTint(id as string) as string
    palette = ["0xD97561FF", "0x668FB8FF", "0xB08A66FF", "0x759E85FF", "0xC77A85FF", "0x8F7AB8FF", "0x5C949EFF", "0xC7A361FF"]
    h = 5381 mod 8
    for each b in Avatar_utf8(id)
        h = (h * 33 + b) mod 8
    end for
    return palette[h]
end function

function Avatar_utf8(s as string) as object
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(s)
    out = []
    for i = 0 to ba.Count() - 1
        out.Push(ba[i])
    end for
    return out
end function

sub layout()
    s = m.top.size
    for each n in [m.tint, m.image, m.edge]
        n.width = s
        n.height = s
    end for
    m.mask.maskSize = [s, s]
    m.initial.width = s
    m.initial.height = s
    m.font.size = Int(s * 0.36 + 0.5) ' 38sp on a 110dp avatar

    lockSize = Int(s * 30 / 110)
    m.lock.translation = [s - lockSize + Int(lockSize * 0.08), s - lockSize + Int(lockSize * 0.08)]
    m.lockBg.width = lockSize
    m.lockBg.height = lockSize
    iconSize = Int(lockSize * 0.55)
    m.lockIcon.width = iconSize
    m.lockIcon.height = iconSize
    m.lockIcon.translation = [(lockSize - iconSize) / 2, (lockSize - iconSize) / 2]

    kf = Int(s * 11 * 1.72 / 220) ' 11 sp at the 110 dp (220 px) design size
    m.kidsFont.size = kf
    kh = kf * 2
    kw = Int(kf * 4.2)
    m.kidsBg.width = kw
    m.kidsBg.height = kh
    m.kidsLabel.width = kw
    m.kidsLabel.height = kh
    m.kids.translation = [s - kw + Int(kf * 0.5), -Int(kf * 0.2)]
    render()
end sub

sub render()
    p = m.top.profile
    if p = invalid then p = {}
    m.tint.blendColor = avatarTint(Str_orEmpty(p.id))
    name = Str_orEmpty(p.name).Trim()
    if name <> "" then m.initial.text = UCase(Left(name, 1)) else m.initial.text = ""
    url = Url_resolve(p.avatar_url)
    if url <> m.image.uri then m.image.uri = url
    m.mask.visible = (url <> "" and m.image.loadStatus = "ready")
    m.initial.visible = not m.mask.visible
    m.lock.visible = m.top.showBadges and Avatar_isTrue(p.has_pin)
    m.kids.visible = m.top.showBadges and Avatar_isTrue(p.is_child)
end sub

sub onImageStatus()
    ready = m.image.loadStatus = "ready"
    m.mask.visible = ready
    m.initial.visible = not ready
end sub

function Avatar_isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function
