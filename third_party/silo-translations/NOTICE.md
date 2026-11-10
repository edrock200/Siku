# Silo translations (vendored)

Siku's interface translations are drawn from the translation catalogs that ship in two
AGPL-3.0 projects, used under that license:

- `android/`: `android-shared/src/androidMain/res/values*/strings_catalog.xml` from
  Silo-Server/silo-android at 09f43a21 (English, Spanish, German, French, Brazilian Portuguese).
- `roku/`: `locale/*/strings.json` from Silo-Server/silo-roku at 89c6f13
  (catalog release 2026.11.09-7c500c0).

Copyright their authors. Siku matches its own English interface text against these catalogs
(`tools/i18n_build.py`); text Siku has that Silo's apps do not is translated in
`i18n/siku/<language>.json`. To refresh, copy the files again from newer commits and run
`python3 tools/i18n_build.py`.
