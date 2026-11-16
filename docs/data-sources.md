# Карта и системные API

Карта центра Бишкека: © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), [ODbL](https://opendatacommons.org/licenses/odbl/1-0/). Исходная выборка Overpass — 15 ноября 2026 года. Локальный GeoJSON `mobile/assets/maps/bishkek.geojson` содержит здания, дороги и парки; маршруты в `routes.json` построены по OSM-путям `footway/path/pedestrian`, без `access=private`. Это не подтверждение текущей безопасности или доступности.

Оригинальные OSM way/node IDs и полная исходная выборка сохранены в рабочей папке дизайна. В поставке координаты карты округлены до пяти знаков; маршруты сохраняют исходную точность. Публичный запуск требует повторной модерации.

Шрифт Oswald — SIL Open Font License; текст лицензии рядом со шрифтом в `mobile/assets/fonts/Oswald-OFL.txt`.

Использованные первичные документы:

- [Core Motion: CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer)
- [Android: шаги в Health Connect](https://developer.android.com/health-and-fitness/health-connect/features/steps)
- [Android: датчики движения](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion)
- [MapLibre Flutter](https://pub.dev/packages/maplibre_gl)

В версии 1.1 Android использует только аппаратный TYPE_STEP_COUNTER; Health Connect не запрашивается. Разрешение на точную геолокацию запрашивается при старте маршрута, а разрешение на шаги — по отдельной кнопке на главной.

MapLibre GL JS 5.6.2 хранится в `mobile/web/vendor`; лицензия включена рядом. Исходный пакет: https://www.npmjs.com/package/maplibre-gl/v/5.6.2.

## Карта версии 1.1

В поставке используются векторные тайлы [OpenFreeMap](https://openfreemap.org/quick_start/) в схеме OpenMapTiles: 358 тайлов, z8–14, 9 МБ передано, bbox [74.42,42.77,74.80,42.97]. Сборщик `scripts/download_offline_map.py` соблюдает лимиты провайдера: не более 4 одновременных запросов, уникальный User-Agent, менее 3000 тайлов/50 МБ. Манифест содержит исходный URL и SHA-256 каждого файла. Файлы копируются в приватную папку приложения и читаются MapLibre без сети. Веб-версия читает те же файлы с локального хоста.

Названия: Noto Sans Regular, [SIL OFL](https://github.com/googlefonts/noto-fonts/blob/main/LICENSE), лицензия включена в assets/fonts/Noto-OFL.txt. Атрибуция OSM/OpenMapTiles/OpenFreeMap доступна на карте; MAP_NOTICE.txt включён в APK. Старый GeoJSON центра оставлен как исходный материал и больше не используется для отображения карты.
