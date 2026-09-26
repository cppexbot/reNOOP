# План: переделка Explore («Показать все показатели») в стиле Apple Health iOS 26

## Контекст (прочитать первым)

- Репо `~/Documents/GLOOP` — личный форк NOOP, работаем прямо в `main`, без веток и PR.
- В индексе застейджено удаление `android/` (1368 файлов). **Никогда не коммитить его.**
  - Коммитить только так: `git add -- <пути>` по одному, потом `git commit --only -- <пути>`.
  - Не делать `git add -A`, `git stash`, `git restore` по всему дереву.
- Уже переделано в стиле iOS 26 (брать как образец, копировать приёмы):
  - `Strand/Summary/` — Сводка. Карточки `SummaryCard`, `SummaryCardTitleRow`, `SummaryMetricCard`, `SummaryMiniChart` лежат в `SummaryCards.swift`.
  - `Strand/SleepHealth/` — Сон.
  - `Strand/MetricHealth/` — страница показателя `MetricDetailView`. Цвета категорий — `MetricHealthStyle.tint(metric)`, форматирование — `MetricHealthStyle.text`, ряды данных — `MetricHealthSeries`.
  - `Strand/Fitness/` — Тренировки (вкладка, детали, запись, силовые, интервалы).
- Explore сейчас: `Strand/Screens/MetricExplorerView.swift` (522 строки), старый дизайн.
  - Экран построен на `ScreenScaffold` + `liquidScaffoldSky`, `NoopCard`, `SectionHeader(overline:)` и `LiquidPressStyle`.
  - На нём строка «Deep Timeline» (`FullDayChartView`) и подсказка «Сканирование данных…».
  - Показатели сгруппированы по 7 категориям `MetricCatalog.categories` (Heart, Charge, Rest, Effort, Health, Nutrition, Mind), всего 59 показателей.
  - Многие показатели повторяются по источникам: например, «Шаги» есть в apple-health, my-whoop и xiaomi-band.
- Куда ведут ссылки на Explore:
  - `TabRoute.metricExplorer` — строка «Показать все показатели» на Сводке (`SummaryView.swift` ~стр. 371);
  - пункт «Explore» в «Обзоре» (`StrandiOS/App/BrowseView.swift`);
  - `Strand/App/RootView.swift` (`.explore`, macOS);
  - демо `--demo-screen explore` в `StrandiOS/App/StrandiOSApp.swift`.
- В `MetricExplorerView.swift`, кроме самого экрана, лежат живые функции, которыми пользуются другие файлы и тесты. Их сохранить:
  - `ExploreRange`;
  - `VitalReading`, `VitalReadingRow`, `vitalReadingRows`, `vitalReadingDateLabel`;
  - `vo2MaxAttributionSource`, `vo2MaxTrendHasBreak`, `vo2MaxTrendSegmentIds`, `vo2MaxEstimatorDisplayName`;
  - `provenanceDisplayLabel`;
  - `shouldExplainSkinTempFallback`, `shouldExplainShortenedSkinTempSeries`.

## Вкус пользователя (важно)

- Всё 1 в 1 как у Apple на iOS 26, минимализм. Лишние карточки, пояснения и подписи — мусор.
- Не выдумывать UI. Перед дизайном смотреть реальные скриншоты Apple iOS 26:
  - `support.apple.com/ru-ru/guide/iphone/<topicId>/26.0/ios/26.0`, картинки лежат на help.apple.com;
  - Health: `iphcae7451f3`, `iphe3d379c32`;
  - в картинках support.apple.com менять `ios-27-iphone-17-pro` на `ios-26-iphone-16-pro`.
- Пользователь короткий и нетерпеливый: показывать реальные скриншоты из симулятора, а не HTML-макеты.
- После каждого шага: собрать, заснять, закоммитить.

## Что сделать

### 1. «Все показатели» как «Все данные о здоровье» в Health iOS 26

Новый файл `Strand/MetricHealth/AllMetricsView.swift`, `struct AllMetricsView`:
- **Фон и заголовок:** фон `StrandPalette.summaryCanvas`, нативный large title «Все показатели», `.searchable` (поиск по названию на любом языке).
- **Секции по категориям Health**, заголовок секции как `SummarySectionHeader`, порядок как в Health:
  - Активность — Effort: усилие, шаги, активные ккал, зоны;
  - Сердце — пульс, ВСР, пульс в покое, VO₂ max, возраст;
  - Дыхание — дыхание, SpO₂;
  - Температура тела — кожа;
  - Сон — Rest;
  - Измерения тела — вес, жир, мышцы;
  - Питание;
  - Психическое здоровье — стресс, настроение;
  - Charge (Заряд) отдельной первой секцией или вместе с кольцами — решить по скриншоту Health; если сомневаешься, Charge в «Сердце».
  - Маппинг `MetricDescriptor → категория Health` сделать одной чистой функцией и покрыть тестом.
- **Карточка показателя** — такая же, как закреплённые карточки Сводки (`SummaryCard` + `SummaryCardTitleRow`):
  - иконка и название цветом категории (`MetricHealthStyle.tint`);
  - справа дата последнего значения (`SummaryStamp`: «Сегодня», «Вчера», дата);
  - крупное последнее значение с единицей (`MetricHealthStyle.text`);
  - справа мини-график за 7 дней (`SummaryMiniChart`).
  - Нажатие пушит `MetricDetailView`: использовать `TabRoute.metricSourced(key:source:)`, чтобы путь шёл через `NavigationPath`.
- **Дубли по источникам:** одна карточка на `key`. Источник брать по приоритету: у кого самое свежее значение; при равенстве — my-whoop > apple-health > xiaomi-band. Остальные источники и так видны на странице показателя («Источники данных»). Это тоже чистая функция с тестом.
- **Показатели без данных** не показывать карточками. В самом низу одна строка «Показатели без данных (N)» раскрывает простой список (как «Все категории» в Фитнесе). Никаких точек «•» и подсказки «Сканирование…».
- **Загрузка:** один проход по каталогу — последнее значение и 7 точек на показатель через `MetricHealthSeries` / репозиторий, как грузит `MetricDetailView`.
  - Сначала `repo.nonEmptyMetricIDs(MetricCatalog.all)`, потом ряды только для непустых, параллельно (`TaskGroup`).
  - Перезагрузка по `repo.refreshSeq`. `LazyVStack`.

### 2. Подключить и убрать старое

- `TabRoute.metricExplorer` → `AllMetricsView()`. Имя кейса можно оставить или переименовать в `.allMetrics` (поправить Сводку).
- В `BrowseView`: пункт «Explore» → «Все показатели» (иконка `list.bullet`), ведёт на `AllMetricsView`.
- `RootView` (macOS) `.explore` → `NavigationStack { AllMetricsView().tabRouteDestinations() }`.
- Демо `explore` → `NavigationStack { AllMetricsView().tabRouteDestinations() }`.
- Живые функции из `MetricExplorerView.swift` (список выше) перенести в `Strand/MetricHealth/MetricReadings.swift` без изменений, затем удалить `MetricExplorerView.swift` целиком.
  - Проверить grep'ом, что `MetricExplorerView`, `MetricRow`, `probeEmptiness` нигде больше не используются.
- **Deep Timeline** (`FullDayChartView`): убрать отдельную строку. Добавить на странице показателя «Пульс» (`MetricDetailView`, секция «Параметры») строку «Весь день по секундам», которая пушит `FullDayChartView`. Сам `FullDayChartView` не переделывать в этом заходе, только убедиться, что у него есть «назад».
- `CompareView` в этом заходе не трогать.

### 3. Строки

- `Strand/Resources/Localizable.xcstrings` отформатирован вручную. **Никогда не перезаписывать через `json.dump`.**
- Новые ключи вставлять текстом сразу после строки `"strings": {` в формате:
  `    "Key": { "localizations": { "ru": {"stringUnit": {"state": "translated", "value": "…"}} } },`
  После вставки проверить, что файл парсится через `json.loads`. Если ключ уже есть с `ru`, не трогать.

### 4. Тесты (stdlib XCTest, без testify)

- `StrandTests/AllMetricsGroupingTests.swift`: маппинг в категории Health, выбор источника для дублей, сортировка.
- Импорт `@testable import Strand`.

## Сборка и проверка

```bash
cd ~/Documents/GLOOP
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# после добавления или удаления файлов — перегенерировать оба проекта:
python3 - <<'PY'
import re; s=open('project.yml').read()
s=re.sub(r'^name: Strand$','name: StrandNoWatch',s,count=1,flags=re.M)
s=re.sub(r'\n(\s*)- target: NOOPWatch\n(\1  [^\n]*\n)*','\n',s)
open('project-nowatch.yml','w').write(s)
PY
xcodegen generate --spec project-nowatch.yml --project . --quiet && xcodegen generate --quiet
# iOS (симулятор iPhone Air, iOS 26.5):
xcodebuild -project StrandNoWatch.xcodeproj -scheme NOOPiOS -destination 'id=BC6F1BFA-C4B3-4F80-BC34-ED60400B70B0' -derivedDataPath /tmp/noopdd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
# macOS (таргет 13.0 — ContentUnavailableView, UnevenRoundedRectangle, .insetGrouped и т.п. закрывать #available / #if os(iOS)):
xcodebuild -project StrandNoWatch.xcodeproj -scheme Strand -destination 'platform=macOS' -derivedDataPath /tmp/noopdd-mac CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
# тесты:
xcodebuild ... -scheme Strand ... test -only-testing:StrandTests/AllMetricsGroupingTests
```

- `project-nowatch.yml` и `StrandNoWatch.xcodeproj` в git не добавлять.
  - `project-nowatch.yml` уже прописан в `.git/info/exclude`.
  - Оба `*.xcodeproj` игнорируются через `.gitignore`.

Скриншоты:

```bash
APP="/tmp/noopdd/Build/Products/Debug-iphonesimulator/NOOP Staging.app"
xcrun simctl install booted "$APP"
xcrun simctl terminate booted com.noopapp.noop
xcrun simctl launch booted com.noopapp.noop --demo-seed --demo-screen explore
sleep 7; xcrun simctl io booted screenshot /tmp/shot.png
```

- Первый запуск после установки иногда показывает экран юридических подтверждений. Не отмечать его, просто запустить ещё раз.
- Полную оболочку с таб-баром даёт запуск без `--demo-screen`; Сводка → «Показать все показатели».
- Прокрутка в симуляторе: swipe с `duration` ≥ 1.5 с, иначе проскакивает.
- Проверить светлую и тёмную тему: `xcrun simctl ui booted appearance light|dark`.

## Критерии готовности

- «Показать все показатели» на Сводке и «Все показатели» в «Обзоре» открывают новый экран: карточки как в Health, секции по категориям Health, поиск, без дублей по источникам, пустые показатели спрятаны в одну строку внизу.
- Нажатие на карточку открывает `MetricDetailView` с нативной кнопкой «назад».
- `MetricExplorerView.swift` удалён, живые функции перенесены, iOS и macOS собираются, новые тесты зелёные.
- Скриншоты в светлой и тёмной теме показаны пользователю, коммит сделан без `android/`.
