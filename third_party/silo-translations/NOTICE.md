# Silo translations (vendored)

Siku's interface translations are drawn from the translation catalogs that ship in two
AGPL-3.0 projects, used under that license:

- `android/`: `android-shared/src/androidMain/res/values*/strings_catalog.xml` from
  Silo-Server/silo-android at f66681ed (catalog release 2026.11.16-a0142c1, which includes
  2026.11.16-d08fe43's audiobook detail and player wording): English, Spanish,
  German, French, Brazilian Portuguese, Dutch, Italian, Polish, Turkish, Swedish, Danish,
  Norwegian Bokmål, Finnish, Czech, Croatian, Russian and Ukrainian. Silo's Japanese, Korean,
  Chinese and Arabic catalogs are not vendored: Siku's fonts do not draw those scripts.
- `roku/`: `locale/*/strings.json` from Silo-Server/silo-roku at e09a5e0
  (catalog release 2026.11.15-0ba1666), the same seventeen languages.

Copyright their authors. Siku matches its own English interface text against these catalogs
(`tools/i18n_build.py`); text Siku has that Silo's apps do not is translated in
`i18n/siku/<language>.json`. To refresh, copy the files again from newer commits and run
`python3 tools/i18n_build.py`.
