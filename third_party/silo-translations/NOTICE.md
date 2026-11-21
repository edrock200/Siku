# Silo translations (vendored)

Siku's interface translations are drawn from the translation catalogs that ship in two
AGPL-3.0 projects, used under that license:

- `android/`: `android-shared/src/androidMain/res/values*/strings_catalog.xml` from
  Silo-Server/silo-android at c6dfd52a6 (catalog release 2026.11.20-9403fbd, from 63c898084, which
  makes the device sign-in copy device-neutral and adds catalog languages): English, Spanish,
  German, French, Brazilian Portuguese, Dutch, Italian, Polish, Turkish, Swedish, Danish,
  Norwegian Bokmål, Finnish, Czech, Croatian, Russian, Ukrainian, Hungarian, Romanian, Slovak,
  Slovenian, Bulgarian, Catalan, Lithuanian, Latvian, Estonian, Vietnamese, European Portuguese,
  Indonesian (Android's legacy folder `values-in`) and Malay. Silo's Japanese, Korean, Chinese,
  Arabic, Greek, Hebrew, Hindi and Thai catalogs are not vendored: Siku's fonts do not draw those
  scripts.
- `roku/`: `locale/*/strings.json` from Silo-Server/silo-roku at 5778e47
  (catalog release 2026.11.20-9403fbd), its seventeen languages (English to Ukrainian above);
  silo-roku does not ship the languages after Ukrainian, so those come from the Android catalog alone.

Copyright their authors. Siku matches its own English interface text against these catalogs
(`tools/i18n_build.py`); text Siku has that Silo's apps do not is translated in
`i18n/siku/<language>.json`. To refresh, copy the files again from newer commits and run
`python3 tools/i18n_build.py`.
