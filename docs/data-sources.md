# Карта и системные API

Карта центра Бишкека: © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), [ODbL](https://opendatacommons.org/licenses/odbl/1-0/). Исходная выборка Overpass — 15 ноября 2026 года. Локальный GeoJSON `mobile/assets/maps/bishkek.geojson` содержит здания, дороги и парки; маршруты в `routes.json` построены по OSM-путям `footway/path/pedestrian`, без `access=private`. Это не подтверждение текущей безопасности или доступности.

Оригинальные OSM way/node IDs и полная исходная выборка сохранены в рабочей папке дизайна. В поставке координаты карты округлены до пяти знаков; маршруты сохраняют исходную точность. Публичный запуск требует повторной модерации.

Шрифт Oswald — SIL Open Font License; текст лицензии рядом со шрифтом в `mobile/assets/fonts/Oswald-OFL.txt`.

Использованные первичные документы:

- [Core Motion: CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer)
- [Android: шаги в Health Connect](https://developer.android.com/health-and-fitness/health-connect/features/steps)
- [Android: датчики движения](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion)
- [MapLibre Flutter](https://pub.dev/packages/maplibre_gl)

Health Connect агрегирует шаги; приложение не складывает их с аппаратным счётчиком. Приоритет всегда у одного источника. Разрешение на точную геолокацию запрашивается при старте маршрута, а разрешение на шаги — по отдельной кнопке на главной.

MapLibre GL JS 5.6.2 хранится в `mobile/web/vendor`; лицензия включена рядом. Исходный пакет: https://www.npmjs.com/package/maplibre-gl/v/5.6.2.
