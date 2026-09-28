# UX-аудит NOOP для iOS 26 (Liquid Glass) — сентябрь 2026

Ревью по скиллу `.claude/skills/apple-design` (шаги «Review process» 1–4, формат отчёта скилла), коммит `cbb3ec3c`, 28 сентября 2026.
Режимы скилла: accessibility audit, dark mode, Liquid Glass, navigation structure, onboarding and permissions, forms and data entry, generative AI, component check.

## Design review: NOOP (iPhone, iOS 26)

### Summary

NOOP — офлайн-компаньон ремешка WHOOP. Приложение одето в Apple Health iOS 26: Сводка, Сон, страницы показателей, Тренировки как в Fitness, Коуч как в «Сообщениях». **Тезис дизайна:** данные чужого ремешка должны читаться как родные данные «Здоровья». Каркас это обещание выполняет: нативный `TabView` с вкладкой поиска, настоящий `tabViewBottomAccessory`, системные ✕/✓ и стекло только на функциональном слое. Лучше всего запоминаются две вещи: карточка «Активность», где кольца Apple Watch несут триаду **Заряд · Усилие · Отдых**, и чёрный экран записи тренировки с цифрами 88–120 pt.

**Оценка: Critical issues.** Главные провалы — в доступности, а не во внешнем виде:
- Dynamic Type не работает примерно для 80 % текста, и масштаб дополнительно ограничен размером AX1.
- Цветной текст в светлой теме даёт контраст 2,1–2,8:1, а режим «Увеличить контраст» на него не влияет.
- Основные графики и циферблат сна недоступны VoiceOver и Switch Control.
- В ряде сценариев ломаются данные или обещания:
  - Коуч сам отправляет данные здоровья, хотя подписано «Только по запросу»;
  - запятая в русской клавиатуре не принимается как десятичный разделитель;
  - колёса веса молча округляют уже сохранённые подходы.

Сравнение с Apple показывает: визуально мы близко к 1 в 1, а поведенчески — нет. Apple-компоненты у Apple масштабируются, темнеют при «Увеличить контраст» и озвучиваются. Наши копии этих компонентов этого не делают.

### Контекст (шаг 1)

| | |
|---|---|
| Платформа | iPhone, iOS 26.5 (симулятор iPhone Air, 420×912 pt). Код общий с macOS (`Strand/`), macOS не ревьюился |
| Фреймворк | SwiftUI, iOS 26 API (`glassEffect`, `Tab(role: .search)`, `tabViewBottomAccessory`, `Button(role: .close/.confirm)`) |
| Категория и аудитория | Здоровье и фитнес; владельцы WHOOP 4.0/5.0, sideload, русская и английская локаль |
| Артефакты | Код `Strand/`, `StrandiOS/`, `StrandiOSShared/`, `StrandiOSWidgets/`, `Packages/StrandDesign`. 170+ скриншотов симулятора: светлая и тёмная тема, AX5, «Увеличить контраст», «Уменьшить прозрачность», оболочка с мини-плеером, экран блокировки с Live Activity, Dynamic Island. 22 эталона Apple iOS 26 с `support.apple.com/ru-ru/guide/iphone/<id>/26.0/ios/26.0` (Сводка «Здоровья», «Лекарства», «Полное расписание», будильник «Часов», «Фитнес» — Сводка, Тренировка, пользовательская тренировка, «Экран и яркость», Настройки) и `support.apple.com/ru-ru/guide/watch` («Пульс», «Осознанность») |
| Контраст | Посчитан по WCAG 2.x из hex-токенов (`Palette.swift`, `NoopVisualStyle.swift`), не на глаз по JPEG. «Semibold» не считается bold, поэтому для текста 17 pt semibold порог 4,5:1 |
| Цель | Полный аудит всех экранов по одному плюс план исправлений |

**Что нельзя было проверить.** Эти ограничения — пределы проверки, а не замечания:
- **VoiceOver, Switch Control и Voice Control в симуляторе не прогонялись.** Выводы о них сделаны по коду: `accessibilityLabel/Element/Action`. Каждый такой вывод помечен «по коду».
- **Reduce Motion** проверен только по коду: статичный скриншот движения не покажет.
- **AX5 ограничен.** Корень ограничивает Dynamic Type значением `...accessibility1`, поэтому кадры «AX5» на деле показывают AX1. Это само по себе находка CR-1.
- **Виджеты сняты не были.** Галерея виджетов в симуляторе пуста, а временный harness требует правки кода. Виджеты проверены только по коду.
- **Демо-данные (`--demo-seed`) странные:** ночь длиной 21 ч (16:00–12:59), «Выспались на 280 %», пульса нет. Эти значения не оценивались.
- **BLE, микрофон и реальные уведомления в симуляторе недоступны.** Голосовой ввод Коуча и резервный будильник проверены только по коду.

**Где лежат скриншоты.** В репозиторий они не коммитятся. Ниже везде указано имя кадра `режим/экран`; снимок повторяется командой:

```bash
xcrun simctl launch --terminate-running-process booted com.noopapp.noop --demo-seed --demo-screen <экран> [флаги]
```

Режимы съёмки:
- `light` и `dark` — `xcrun simctl ui booted appearance …`;
- `ax` — `xcrun simctl ui booted content_size accessibility-extra-extra-extra-large`;
- `ic` — `xcrun simctl ui booted increase_contrast enabled`;
- `rt` — `xcrun simctl spawn booted defaults write com.apple.Accessibility EnhancedBackgroundContrastEnabled -bool true`, затем перезапуск приложения;
- `shell` — запуск без `--demo-screen`; для мини-плеера добавить `--demo-running workout`, для Live Activity — `--demo-activity hr`.

### Справочники (шаг 2)

Перед каждым экраном загружался `references/hig-lookup.md`.

**Всегда:** `design-principles.md`, `designing-for-ios.md`, `liquid-glass.md`, `accessibility.md`, `dark-mode.md`, `color.md`, `typography.md`, `layout.md`, `sf-symbols.md`, `motion.md`, `writing.md`.

**По месту:**
- **Навигация и каркас:** `tab-bars.md`, `toolbars.md`, `sheets.md`, `modality.md`, `searching.md`, `search-fields.md`, `scroll-views.md`, `materials.md`, `popovers.md`, `home-screen-quick-actions.md`.
- **Списки и данные:** `lists-and-tables.md`, `charts.md`, `charting-data.md`, `gauges.md`.
- **Контролы:** `buttons.md`, `context-menus.md`, `menus.md`, `pickers.md`, `segmented-controls.md`, `steppers.md`, `toggles.md`, `page-controls.md`.
- **Ввод и обратная связь:** `text-fields.md`, `entering-data.md`, `virtual-keyboards.md`, `undo-and-redo.md`, `feedback.md`, `alerts.md`, `action-sheets.md`, `loading.md`, `progress-indicators.md`.
- **Уведомления и системные поверхности:** `notifications.md`, `managing-notifications.md`, `live-activities.md`, `widgets.md`, `controls.md`, `app-shortcuts.md`.
- **Первый запуск и настройки:** `onboarding.md`, `launching.md`, `privacy.md`, `managing-accounts.md`, `settings.md`.
- **ИИ, жесты, движение, прочее:** `generative-ai.md`, `machine-learning.md`, `playing-haptics.md`, `gestures.md`, `going-full-screen.md`, `voiceover.md`, `maps.md`.

Все 176 цитат ниже сверены скриптом с текстом этих файлов дословно. Заголовок раздела указан как `файл.md › Раздел`.

### Приоритеты

| Метка | Значение (шкала скилла) |
|---|---|
| **Critical** | доступность, сломанное поведение, потеря данных, неправда о данных |
| **Improvement · High** | реальное трение или явное нарушение конвенций iOS 26 |
| **Improvement · Medium** | неоптимальный паттерн, пропущенный системный компонент, мелкая непоследовательность |
| **Craft · Low** | полировка |

---

## Critical

### CR-1. Dynamic Type не работает для ~80 % текста, масштаб ограничен AX1 — Critical

**What.**
- Весь «фирменный» кегль в `Packages/StrandDesign/Sources/StrandDesign/Typography.swift` (`pro`, `rounded`, `number`, `display`, строки 19–21, 39–41, 100–102, 113–115) — это `Font.system(size:)`.
- По коду: 520 строк с фиксированным кеглем в 91 файле (414 текстовых, 106 иконок) против 156 строк с текстовыми стилями.
- `@ScaledMetric` не встречается нигде, `isAccessibilitySize` и `AnyLayout` тоже.
- Корень ограничивает масштаб: `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` (`StrandiOS/App/StrandiOSApp.swift:252`, `Strand/App/StrandApp.swift:66`). Пользователь с AX2–AX5 получает AX1. Стилевой текст растёт максимум до 165 %, фиксированный — до 100 %.
- Комментарий `StrandiOSApp.swift:249–251` утверждает, что StrandFont масштабируется. Это неправда.

Что видно на скриншотах AX5 (`ax/*`):
- **Сводка.** Заголовки карточек выросли до ~28 pt, а значения «76 мс» и «61 уд/мин» остались 24 pt, то есть значение стало мельче заголовка. Заголовки режутся: «Кислород в кр…». «Закреплено» (фиксированные 22 pt) стало мельче ссылки «Изменить».
- **Страница показателя (ВСР), Тренировки, Интервалы, Дневник, Журнал, Lab Book, Пульс, Осознанность, Онбординг** не изменились вообще.
- **«Больше данных о сне».** Подписи оси слиплись в «17192021…», заголовки обрезались до «ВРЕМЯ В…», дата стала крупнее цифры сна.
- **Мастер добавления.** Заголовки секций «WHOOP»/«Другое» огромные, а сами ряды — 17 pt.
- **Коуч.** Ответы тренера растут (MarkdownUI), а ваши сообщения — нет.

**Why.**
- `accessibility.md › Vision`: "Ideally, give people the option to enlarge text by at least 200 percent (or 140 percent in watchOS apps)."
- `typography.md › Supporting Dynamic Type`: "Make sure your app’s layout adapts to all font sizes." и "Maintain a consistent information hierarchy regardless of the current font size."
- `typography.md › Using system fonts`: "Using text styles with the system fonts also ensures support for Dynamic Type and larger accessibility type sizes (where available), which let people choose the text size that works for them."

**Fix.** 431 из 493 литеральных размеров (87 %) совпадают с дефолтами текстовых стилей. Одна правка в `Typography.swift` включает масштабирование примерно в 430 местах, а на размере Large пиксели не меняются:

```swift
// Packages/StrandDesign/Sources/StrandDesign/Typography.swift
private static func textStyle(for size: CGFloat) -> Font.TextStyle? {
    switch size {
    case 11: .caption2; case 12: .caption; case 13: .footnote; case 15: .subheadline
    case 16: .callout; case 17: .body; case 20: .title3; case 22: .title2
    case 28: .title; case 34: .largeTitle; default: nil
    }
}
public static func pro(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    textStyle(for: size).map { .system($0, weight: weight) } ?? .system(size: size, weight: weight)
}
public static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    (textStyle(for: size).map { .system($0, design: .rounded, weight: weight) }
        ?? .system(size: size, weight: weight, design: .rounded)).monospacedDigit()
}
```

Затем:
1. Крупные числа (24/34/64/88) перевести на `@ScaledMetric(relativeTo: .largeTitle) private var figure: CGFloat = 34`. Изменения во вьюхах: `SummaryCards.swift`, `MetricDetailView.swift:188–204`, `SleepPageCards.swift:34–53`, `LiveView.swift:184`, `HRVSnapshotView.swift:172`.
2. Многоколоночные ряды перестраивать через `AnyLayout`:
   ```swift
   @Environment(\.dynamicTypeSize) private var dts
   let row = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
   ```
   Места: карточка «Активность» (`SummaryCards.swift:127–173`), плитки сна (`SleepMetricCards.swift:78–104`), подходы (`LiftSessionEditSheet.swift:117–175`), зоны (`WorkoutDetailView.swift:167–176, 289–304`), ряды настроек с длинным значением.
3. Вместо фиксированных высот — `.frame(minHeight:)`: `BrowseView.swift:106` (51 pt), `SettingsView.swift:112–121` (142 pt).
4. Снять потолок `...accessibility1` в `StrandiOSApp.swift:252`, а ограничение оставить точечно, только на гейджах: `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`.

**Скриншоты:** `light/summary` vs `ax/summary`; `ax/metric-hrv`; `ax/sleepmore`; `ax/addwizard`; `ax/coach`.

---

### CR-2. Цветной текст в светлой теме ниже 3:1 и не темнеет при «Увеличить контраст» — Critical

**What.**
- **Заголовки карточек** в оттенке категории: 17 pt semibold на белой карточке (`SummaryCards.swift:68–70, 124, 148–149`, `SleepMetricCards.swift:101,106`, цвета — `MetricHealthStyle.swift:238–249`):
  - Заряд/Питание `#34C759` — 2,22:1;
  - Усилие/Температура `#FF9500` — 2,20:1;
  - Дыхание `#00C7BE` — 2,12:1;
  - Кислород `#32ADE6` — 2,54:1;
  - Mind `#30B0C7` — 2,57:1;
  - ВСР/Пульс `#FF2D55` — 3,65:1;
  - Активность `#FA3C1E` — 3,66:1;
  - Тело `#AF52DE` — 4,13:1;
  - проходит только Отдых `#5E5CE6` — 5,06:1.
- **Подписи колонок Активности** (`Palette.swift:298–300`): «Усилие» `#2BB800` — 2,64:1, «Отдых» `#00A9CC` — 2,78:1, «Заряд» `#F5174F` — 4,10:1.
- **Тренировки.** Значения «Работа 0:30» и «Отдых 0:15» (28 pt, `IntervalTimerView.swift:128–131`) — 2,78:1 и 2,64:1. Длительности `fitnessTime` `#C29200` — 2,84:1. «8 × 0:30 / 0:15» `#2BB800` на `fitnessCard` `#E3F5D6` — 2,30:1. Зоны 2/3/4 (15 pt) — 3,07 / 3,30 / 2,91.
- **Таймер мини-плеера** (`NowRunning.swift:93,120`) — 2,64:1 и 2,84:1 при 15 pt.
- **Белые глифы на цветной заливке:** ✓ на `#2BB800` — 2,64:1 (8 шторок); белое на мятном `#69DDB8` в тёмной теме — 1,66:1 (`BarButtons.swift:46–62`, выбранный день недели `SleepScheduleComponents.swift:191`); «Да» в Журнале, белое на `#30B0C7` — 2,57:1 (`JournalView.swift:487–508`).
- **Нейтральные токены:** `textTertiary` `#7D808A` — 3,94:1 на карточке и 3,58:1 на канвасе (подписи осей, сноски). `statusWarning` `#C2792E` — 3,46:1. `messageMeta` (11 pt) — 3,44:1.
- **«Увеличить контраст».** `Color(light:dark:)` (`Palette.swift:33–71`) выбирает вариант только по `userInterfaceStyle`: вариантов для высокого контраста нет, `colorSchemeContrast` нигде не читается. На кадрах `ic/summary` и `ic/intervals` все наши цвета остались прежними, как на `light/*`; изменился только системный таб-бар. Системные цвета записаны hex-кодом: `#007AFF` в обеих темах (`AppearanceLock.swift:15,19–20`) даёт 4,02:1 на белом. Системный синий при «Увеличить контраст» стал бы `#0040DD` (7,56:1).

**Why.**
- `accessibility.md › Vision` (таблица): "Up to 17 pts | All | 4.5:1".
- `accessibility.md › Vision`: "If your app doesn’t provide this minimum contrast by default, ensure it at least provides a higher contrast color scheme when the system setting Increase Contrast is turned on."
- `color.md › Best practices`: "If you define a custom color, make sure to supply light and dark variants, and an increased contrast option for each variant that provides a significantly higher amount of visual differentiation."
- `color.md › System colors`: "Avoid hard-coding system color values in your app."

**Fix.**
1. **Высокий контраст в токене** (`Palette.swift`):
   ```swift
   init(light: String, dark: String, lightHC: String? = nil, darkHC: String? = nil) {
       // …
       self.init(UIColor { t in
           let dark = t.userInterfaceStyle == .dark, hc = t.accessibilityContrast == .high
           let hex = dark ? (hc ? darkHC ?? darkHex : darkHex) : (hc ? lightHC ?? lightHex : lightHex)
           return UIColor(hex: hex)
       })
   }
   ```
2. **Текст категорий.** Оттенок оставить на глифе, а текст сделать отдельным токеном с тем же тоном и контрастом ≥ 4,5:1 на белом:
   | Категория | Светлый вариант |
   |---|---|
   | зелёный | `#23863C` |
   | оранжевый | `#AB6400` |
   | бирюзовый | `#00837E` |
   | голубой | `#157DAC` |
   | Mind | `#238090` |
   | сердце | `#EA002D` |
   | тело | `#A945DB` |
   | активность | `#E42405` |

   Для Фитнеса: `activityExerciseText` light `#1A7A00` (4,92:1 на `#F2F2F7`), `activityStandText` `#007C96` (4,86:1), `fitnessTime` `#8A6700` (5,22:1). Тёмные варианты не менять: они проходят (≥ 4,83:1).
3. **Системные цвета** брать системными: `Color.blue`, `Color.green`, `Color.orange`. Фоны — `Color(uiColor: .systemGroupedBackground)` / `.secondarySystemGroupedBackground`: так появятся HC-варианты и elevated-фон в шторках.
4. **Глифы на заливке.** Цвет глифа выбирать по яркости заливки: на `#69DDB8` ставить `#17181C` (10,67:1), на зелёной ✓ в светлой теме — чёрный (7,96:1).
5. **Нейтральные токены:** `textTertiary` light → `#72757E` (4,6:1); подписи осей → `textSecondary` (7,11:1).

**Скриншоты:** `light/summary`, `ic/summary` (совпадают), `light/intervals`, `shell/summary-running` (таймер мини-плеера).

---

### CR-3. Графики немы или врут для VoiceOver — Critical (по коду)

**What.**
- **Главный график страницы показателя** (`Strand/MetricHealth/MetricHealthChart.swift:37–38`) закрыт через `.accessibilityElement(children: .ignore)` с подписью `window.range.label`. В ru VoiceOver произносит одну букву: «Н», «М», «6М» или «Г». Вместе с этим пропадают Audio Graphs и элементы на каждый столбец, которые Swift Charts даёт бесплатно. `accessibilityChartDescriptor` не используется нигде.
- **Графики сна на Canvas:**
  - недельный (`SleepRangeChart.swift:48–49`) озвучивает только среднюю длительность, а при `nil` — пустую строку;
  - график стадий (`SleepStagesChart.swift:58–59`) — только суммы;
  - график недосыпа (`SleepMoreDataView.swift:611`) скрыт без замены.
- **«Весь день по секундам»** (`OverviewHRChart.swift:516,529`) для SpO₂, температуры и HRV говорит «Heart rate, 24 hours … average 36.6 bpm», причём «24 hours» остаётся и при зуме.
- **Столбцы Live** читаются как «Hour 9.5» (`LiveView.swift:285–289`).
- **Сегменты Н·М·6М·Г** озвучиваются буквами (`MetricDetailView.swift:77`, `SleepMoreDataView.swift:101`).

**Why.**
- `charts.md › Enhancing the accessibility of a chart`: "you get a default implementation of Audio graphs, in addition to a default accessibility element for each mark (or group of marks) that describes its value."
- `charts.md › Enhancing the accessibility of a chart`: "Health offers an accessibility label for each bar in the Steps chart, because the purpose of the chart is to give people their actual step count for each tracking period."
- `voiceover.md › Descriptions`: "Make charts and other infographics fully accessible. Provide a concise description of each infographic that explains what it conveys."

**Fix.**

```swift
// Strand/MetricHealth/MetricHealthChart.swift — удалить строки 37–38, подписать метки
BarMark(x: .value("Day", p.start, unit: .day), y: .value(metric.title, p.value))
    .accessibilityLabel(Text(p.start, format: .dateTime.weekday(.wide).day().month(.wide)))
    .accessibilityValue(Text(MetricHealthStyle.text(p.value, metric: metric)))
// + .accessibilityChartDescriptor(MetricChartDescriptor(window: window, metric: metric))

// Strand/SleepHealth/SleepRangeChart.swift — дочерние элементы по ночам
.accessibilityElement(children: .contain)
.accessibilityChildren {
    ForEach(window.bars) { bar in
        Rectangle()
            .accessibilityLabel(Text(bar.start, format: .dateTime.weekday(.wide).day().month()))
            .accessibilityValue(Text("\(clockLabel(bar.onsetMin))–\(clockLabel(bar.wakeMin))"))
    }
}

// Сегменты: читать слово, а не букву
Text(range.label).accessibilityLabel(Text(range.spokenName))   // «Неделя», «Месяц», «6 месяцев», «Год»
```

Для `OverviewHRChart` передавать `axTitle` и `axUnit` метрики и добавить `.accessibilityZoomAction`.

**Скриншоты:** `light/metric-hrv`, `light/sleepmore`, `light/sheet-fullday`. Проверка — Accessibility Inspector.

---

### CR-4. Циферблат расписания сна управляется только перетаскиванием — Critical (по коду)

**What.**
- Единственное adjustable-действие (`Strand/SleepSchedule/SleepScheduleDial.swift:35–42`) сдвигает **оба** конца на ±15 мин.
- Изменить отдельно отбой, подъём или длительность через VoiceOver, Switch Control или Voice Control нельзя: это возможно только жестом `DragGesture` (`:155`).
- В `Strand/SleepSchedule/` нет ни `DatePicker`, ни `Stepper`.
- Дуга на треке (`#FFFFFF` на `#E3E3E8`) даёт 1,28:1. Это единственный признак выбранного диапазона.

**Why.**
- `accessibility.md › Mobility`: "Offer alternatives to gestures. Make sure your UI’s core functionality is accessible through more than one type of physical interaction."
- `voiceover.md › Descriptions`: "If people can interact with the infographic to get more or different information, make these interactions available to people using VoiceOver, too."

**Fix.**

```swift
// Strand/SleepSchedule/SleepScheduleDial.swift
.accessibilityRepresentation {
    DatePicker("Bedtime", selection: bedDate, displayedComponents: .hourAndMinute)
    DatePicker("Wake Up", selection: wakeDate, displayedComponents: .hourAndMinute)
}
```

Время над циферблатом («ОТХОД КО СНУ 22:30») сделать кнопкой, которая открывает `.wheel`-пикер: так у Apple в «Часах». Дуге дать контурную обводку `hairlineStrong` при `colorSchemeContrast == .increased`.

**Скриншот:** `light/scheduleedit`.

---

### CR-5. Ключевые контролы без понятной подписи VoiceOver — Critical (по коду)

**What.**
- **Главная цифра экрана записи и сессии в зале.** `.accessibilityLabel("Elapsed time")` / `("Session")` на `TimelineView` (`LiveWorkoutView.swift:164–167`, `LiftSessionView.swift:398–401`) заменяет сам текст часов: VoiceOver говорит «Elapsed time» и не говорит время.
- **Интервалы.** Шесть кнопок −/+ (`IntervalTimerView.swift:134–152`) без контекста: VoiceOver трижды читает «minus» и не говорит, что меняется — Работа, Отдых или Раунды. От 5 с до 10 мин нужно 119 нажатий.
- **✓ в шторках** на iOS 26 (`Strand/App/BarButtons.swift:46–49`) подписана именем символа, то есть «галочка», а не «Готово». Запасной вариант называет её «Save», даже когда шторка только для просмотра.
- **Кнопки Live Activity** (`StrandiOSWidgets/LiveActivityChrome.swift:59–66`) без подписи. Интент паузы называется «Pause» и при значке ▶ (`LiveActivityIntents.swift:35`).
- **Состояния подходов** читаются как имена символов, например «record.circle» (`LiftSessionView.swift:286–297`).
- **«Что читает NOOP»** озвучивается по-английски: «Live heart rate: да» (`DeviceReadsView.swift:57–73`).

**Why.**
- `voiceover.md › Descriptions`: "Provide alternative labels for all key interface elements."
- `steppers.md › Best practices`: "Make the value that a stepper affects obvious."

**Fix.**

```swift
// LiveWorkoutView.swift / LiftSessionView.swift
RecordingClockText(text: Self.stopwatch(s))
    .accessibilityLabel(Text("Elapsed time"))
    .accessibilityValue(Duration.seconds(s).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))

// IntervalTimerView.swift — один регулируемый элемент на блок
block
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(title)).accessibilityValue(Text(value))
    .accessibilityAdjustableAction { $0 == .increment ? plus() : minus() }

// BarButtons.swift
SheetConfirmButton(action: …).accessibilityLabel(Text("Done"))

// LiveActivityChrome.swift
ActivityControl(intent: …, symbol: …, label: paused ? "Resume" : "Pause")   // + .accessibilityLabel(Text(label))

// DeviceReadsView.swift
spokenFeature: String(localized: "Live heart rate")
```

**Скриншоты:** `shell/recording`, `light/intervals`.

---

### CR-6. Мелкие тап-зоны и отмена, исчезающая по таймеру — Critical

**What.**
- **`NoticeCard`:**
  - ✕ имеет кадр 24×24 со стилем `.plain` (`Strand/App/NoticeCard.swift:62–69`) — меньше минимальных 28 pt;
  - текстовая кнопка действия («Отменить», «Открыть устройства») — 15 pt, около 20 pt по высоте (`:53–57`);
  - заголовок с `lineLimit(1)` и `minimumScaleFactor(0.85)` (`:44–45`).
- **Удаление ночи** (`SleepHealthView.swift:399–404`): длинная фраза «Сон удалён. NOOP больше не будет находить сон между…» обрезается, а сама отмена исчезает через `Task.sleep` 7 с.
- **HUD-подтверждение** («Скопировано», «Резервная копия создана») живёт 1,6 с (`ConfirmationHUD.swift:36`), не объявляется VoiceOver (`AccessibilityNotification` в проекте не используется ни разу) и въезжает сверху даже при Reduce Motion (`:90`).
- **Другие мелкие зоны:**
  - «!» у недоставленного сообщения Коуча — 24×24 (`CoachView.swift:458–462`);
  - кнопка отправки — 38×28 (`:627–632`);
  - ⓘ — 30×30 (`InfoButton.swift:46–50`);
  - «Изменить» на Сводке — около 22 pt по высоте;
  - стрелки ‹ › — 44×36;
  - кружки дней недели — 38 pt.

**Why.**
- `accessibility.md › Mobility` (таблица): "iOS, iPadOS | 44x44 pt | 28x28 pt".
- `accessibility.md › Cognitive`: "Views and controls that auto-dismiss on a timer can be problematic for people who need longer to process information".
- `voiceover.md › Navigation`: "Inform VoiceOver when visible content or layout changes occur."
- `feedback.md › Best practices`: "Make sure all feedback is accessible."

**Fix.**

```swift
// Strand/App/NoticeCard.swift — визуал тот же, зона 44×44, заголовок переносится
Image(systemName: "xmark").font(.caption.bold())
    .frame(width: 24, height: 24).background(.fill.tertiary, in: Circle())
    .frame(width: 44, height: 44).contentShape(Circle())
Button(actionTitle, action: action).frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
Text(title)            // убрать .lineLimit(1) и .minimumScaleFactor(0.85)

// Strand/SleepHealth/SleepHealthView.swift:404 — удалить Task.sleep: карточка живёт до ✕ или ухода с экрана

// Strand/App/ConfirmationHUD.swift
AccessibilityNotification.Announcement(label).post()
.transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
```

**Скриншот:** `light/notices` (галерея всех состояний `NoticeCard`).

---

### CR-7. Экран условий и онбординг лежат слоем поверх живого таб-бара — Critical (по коду)

**What.** `StrandiOSApp.swift:493–518`: `ZStack { RootTabView; OnboardingWizard; TermsGateView }`. Шлюзы первого запуска — обычные слои без `accessibilityHidden` у `RootTabView` и без трейта `.isModal`. VoiceOver, Switch Control и Full Keyboard Access могут дойти до вкладок и Сводки под экраном условий и нажать их, не приняв условия.

**Why.** `modality.md › Modality`: "Modality is a design technique that presents content in a separate, dedicated mode that prevents interaction with the parent view and requires an explicit action to dismiss."

**Fix.**

```swift
// StrandiOS/App/StrandiOSApp.swift
RootTabView(...)
    .accessibilityHidden(!demoBypass && (!onboarded || acceptedTerms != Terms.currentVersion))
// у TermsGateView и OnboardingWizard
.accessibilityAddTraits(.isModal)
```

Лучший вариант — показывать оба шлюза через `.fullScreenCover` с `.interactiveDismissDisabled()`.

**Скриншот:** чистая установка без флагов. Проверка VoiceOver — на устройстве.

---

### CR-8. «Спокойствие» передаёт ритм только вибрацией — Critical (по коду)

**What.**
- В режиме Calm цветок стоит на месте (`BreathingView.swift:775–782`: `progress = 0.35`), а на экране только «Follow the rhythm on your wrist».
- `canRun` не проверяет `HapticPrefs.breathing`. Если вибрация дыхания выключена, сессия идёт 3 минуты и ничего не передаёт. Звуковые подсказки в Calm тоже не звучат.

**Why.** `playing-haptics.md › Best practices`: "Make haptics optional. Let people turn off or mute haptics, and make sure people can still enjoy your app or game without them."

**Fix.**

```swift
// Strand/Screens/BreathingView.swift
private var canRun: Bool { hub.controller.canBuzz && restingBand && HapticPrefs.enabled(HapticPrefs.breathing) }
// BiofeedbackController: @Published private(set) var calmBeat = 0; calmBeat &+= 1 в scheduleCalmStep
controller.$calmBeat.dropFirst().sink { [weak self] _ in self?.pulse() }   // 0.35 → 0.45 → 0.35; при Reduce Motion — только opacity
```

**Скриншот:** `light/breathe-session`.

---

### CR-9. Текст виджетов мельче 11 pt с контрастом 3,9:1 — Critical (по коду)

**What.**
- Подписи колец — 9 pt (`StrandiOSWidgets/NOOPWidget.swift:182`), `minimumScaleFactor(0.7)` → 10,5 pt (`:149`).
- `HeartRateWidget.swift:163,178` — 10 pt; `:234` — 9 pt.
- `StressWidget.swift:197,221,225` — 10 pt; `:301` — 9 pt.
- `CoachBriefWidget.swift:107,110` — 11 × 0,8 = 8,8 pt.
- Цвет подписей — `textTertiary` `#7D808A` на белом: 3,94:1.

**Why.**
- `widgets.md › Displaying text in widgets`: "In general, display text using fonts at 11 points or larger."
- `accessibility.md › Vision`: "Strive to meet color contrast minimum standards."

**Fix.** `.font(.caption2)` вместо 9–10 pt. `.foregroundStyle(.secondary)` вместо `textTertiary` (`WidgetScoreRing:407`, `statCell:349/352`). Удалить `.minimumScaleFactor(0.7/0.8)`.

**Скриншот:** в симуляторе недоступен; проверять в Xcode Preview `.systemSmall`.

---

### CR-10. Коуч сам отправляет данные здоровья, хотя подписано «Только по запросу» — Critical

**What.**
- Под шапкой чата написано «Ваш сервер · 🔒 Только по запросу» (`CoachView.swift:278–295`).
- При пустом чате и включённом «Использовать мои данные» `startBriefIfNeeded()` (`Strand/AI/AICoach.swift:831–848`) сам собирает `buildFullContext()` и отправляет провайдеру. Это происходит при каждом открытии пустого чата (`CoachView.swift:129`), сразу после включения тумблера (`:151–153`) и после «Очистить разговор».
- Футер «что уходит» (`CoachSettingsView.swift:196–201`) виден только после включения и не называет получателя.
- Строки разрешений Health и Bluetooth обещают «Nothing leaves your device» (`StrandiOS/Resources/Info.plist:62–65`), хотя Коуч по согласию отправляет ВСР, сон и пульс в OpenAI, Anthropic или Gemini.

**Why.**
- `generative-ai.md › Privacy`: "Be transparent by making sure people know their information may be sent to a server, showing them what’s shared, and helping them understand what data may be stored off-device or used for training."
- `privacy.md › Best practices`: "Be transparent about how your app collects and uses people’s data."

**Fix.**
1. Убрать автозапуск брифа из `.task` и `onChange(dataConsent)` в `CoachView.swift`. «Бриф на сегодня» сделать первым чипом подсказок: нажатие на него и есть «спросил».
2. Футер показывать всегда: `Text("\(coach.provider.displayName) receives charge, sleep, HRV and workouts when you ask.")`.
3. В строках разрешений убрать «Nothing leaves your device» (см. ON-3).

**Скриншоты:** `light/coach-empty`, `light/coach-settings`.

---

### CR-11. Ввод данных портит данные: запятая не принимается, колёса веса округляют сохранённое — Critical

**What.**
- **Дистанция при ручном добавлении** разбирается через `Double(t)` (`Strand/Fitness/ManualWorkoutSheet.swift:231`). На русской `.decimalPad` дробный разделитель — запятая, а `Double("5,2") == nil`. Проверено в симуляторе: после ввода «5,2 км» форма показывает «Расстояние должно быть в диапазоне 0–1 000 km.» (ещё и с английским «km»), а ✓ остаётся неактивной. Дробную дистанцию ввести нельзя.
- **Вывод всегда через точку.** `LiftFormat.trim` ставит «.»: «82.5 кг», «45s». Превью импорта программы показывает «kg» даже пользователю с фунтами (`LiftProgramImportSheet.swift:153–157`).
- **Колёса веса в редакторе подхода** (`LiftSetEditor.swift:40–49, 128–131`) округляют до шага 0,5 кг / 1 lb и обрезают значения выше 300 кг / 660 lb / 100 повторов. `save()` записывает вес всегда, даже если поменяли только RPE или отметку разминки. Примеры: 61,25 → 61,5; 60 кг (132,28 lb) → 132 lb = 59,87 кг; 320 → 300.
- **Целые поля** («Повторы», «Рабочие подходы») открываются на `.decimalPad`, и ввод «8,5» молча превращается в `nil` (`LiftProgramItemSheet.swift:93–96, 263–271`; `Components.swift:103–105`).

**Why.**
- `text-fields.md › Best practices`: "Don’t assume the actual presentation of data, however, as formatting can vary significantly based on people’s locale."
- `virtual-keyboards.md › Best practices`: "Choose a keyboard that matches the type of content people are editing."
- `entering-data.md` (вступление): "When you need information from people, design ways that make it easy for them to provide it without making mistakes."

**Fix.**

```swift
// Разбор с учётом локали — одна функция для всех полей
static func number(_ s: String, locale: Locale = .current) -> Double? {
    try? Double(s.trimmingCharacters(in: .whitespaces), format: .number.locale(locale))
}
// Вывод
static func trim(_ v: Double) -> String { v.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) }
static func duration(_ s: Int) -> String { Duration.seconds(s).formatted(.units(allowed: [.minutes, .seconds], width: .narrow)) }
// LiftSetEditor: запомнить исходное положение колёс и не писать вес, если колесо не трогали
let kg = weightTouched ? LiftFormat.kilograms(fromDisplay: weight, system: system) : originalKg
// Целые поля
.keyboardType(.numberPad)
```

**Скриншот:** `shell/manual-comma` — «Добавить тренировку» (вкладка «Тренировки» → «+»), вид «Бег», дистанция «5,2».

---

### CR-12. Голосовой ввод Коуча сломан — Critical (по коду, микрофона в симуляторе нет)

**What.** `CoachView.swift:625–647, 676–694`:
- Первая частичная расшифровка делает черновик непустым. Кнопка «стоп» заменяется на «Отправить», хотя запись продолжается.
- Расшифровка затирает набранный текст (688/692), а «стоп» дописывает её ещё раз (682). Получается дубль.
- При запрете сама кнопка микрофона серая и ничего не объясняет. Причина есть только в `accessibilityHint`, пути в Настройки нет.
- Разрешения «Речь» и «Микрофон» запрашиваются при открытии экрана (`.task`, `:663–668`), а не по касанию.

**Why.**
- `feedback.md › Best practices`: "Show people when a command can’t be carried out and help them understand why."
- `privacy.md › Requesting permission`: "Ideally, wait to request permission until people actually use an app feature that requires access."

**Fix.**

```swift
@State private var dictationBase = ""
if voiceInput.isRecording { stopButton } else if hasDraft { sendButton } else { micButton }
dictationBase = draft
voiceInput.startTranscribing { draft = [dictationBase, $0].filter { !$0.isEmpty }.joined(separator: " ") }
voiceInput.stopTranscribing { _ in }                          // не дописывать повторно
// .denied: тап → openURL(URL(string: UIApplication.openSettingsURLString)!)
// удалить .task { requestAuthorization } — toggleVoice() спросит по касанию
```

---

## Improvements

Замечания разобраны по экранам, в каждом разделе — в порядке убывания серьёзности. Сквозные проблемы CR-1 (Dynamic Type) и CR-2 (контраст) здесь не повторяются.

### 1. Каркас: таб-бар, аксессуар, тулбары, шторки, поиск

**K-1. Поиск «Обзора» находит только 9 названий разделов — Improvement · High**
- **What:** `StrandiOS/App/BrowseView.swift:53–58` фильтрует только строки категорий. Запросы «ВСР», «VO₂», «пульс покоя» дают «Нет результатов», хотя страницы этих показателей есть. Поиск в «Здоровье» находит типы данных.
- **Why:** `searching.md › Best practices`: "Aim to make your app’s content searchable through a single location."
- **Fix:** в режиме поиска добавить секцию показателей:
  ```swift
  ForEach(AllMetricsCatalog.oneSourcePerKey(MetricCatalog.all.filter {
      $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }, latestDay: [:])) { m in
      NavigationLink(value: TabRoute.metricSourced(key: m.key, source: m.source)) { Label(m.title, systemImage: m.icon) }
  }
  ```
- **Скриншот:** `shell/browse`.

**K-2. Один экран открывается то переходом, то шторкой; быстрое действие показывает корень вкладки в шторке — Improvement · High**
- **What:** в `StrandiOS/App/RootTabView.swift`:
  - Что вами движет, Lab Book и Коуч открываются шторкой (132–146), Журнал — тоже шторкой (157–161);
  - Тренды открываются переходом (147–151);
  - «Начать тренировку» из быстрых действий показывает **корень вкладки «Тренировки»** в шторке (259);
  - «Устройства» открываются тремя способами;
  - в 207–209 одна шторка закрывается и другая открывается в том же такте.
- **Why:** `modality.md › Best practices`: "Take care to avoid creating a modal experience that feels like an app within your app."
- **Fix:** все внешние входы делать как у `.trends`: `selectedTab = 4; tabPaths[4] = NavigationPath([MoreDestination.coach])`. Для `.startWorkout` — `selectedTab = 1`. После этого три `.sheet` (112–124) удалить.
- **Скриншот:** долгое нажатие на иконку → «Начать тренировку».

**K-3. Мини-плеер закрывает подсказки Коуча; Коуч прячет таб-бар — Improvement · High**
- **What:**
  - `CoachView.swift:94` делает `.toolbar(.hidden, for: .tabBar)`, но аксессуар тренировки остаётся. Он ложится на ряд подсказок над полем ввода: текст «…качество важнее объёма — спланируй тр…» виден под капсулой «Силовая 2:20».
  - Если открыть Коуча из «Обзора», пропадают и вкладки.
  - В «Сообщениях» таб-бар скрыт, потому что вкладок там нет.
- **Why:** `tab-bars.md › Best practices`: "Make sure the tab bar is visible when people navigate to different sections of your app."
- **Fix:** удалить строку 94. Поле ввода в `safeAreaBar(edge: .bottom)` само встанет над таб-баром и аксессуаром.
- **Скриншот:** `shell/coach-from-browse`.

**K-4. Мини-плеер: неясное двойное касание VoiceOver, нет компактного вида, полный экран не смахивается — Improvement · Medium**
- **What:**
  - `NowRunning.swift:196–200`: `onTapGesture` плюс `.combine` с вложенной кнопкой «Пауза». Двойное касание VoiceOver может нажать паузу вместо того, чтобы открыть тренировку.
  - `:115`: ✓ подписана «Next», а на экране сессии то же действие называется «Set done».
  - Нет `tabViewBottomAccessoryPlacement`, поэтому в свёрнутом таб-баре строка не ужимается.
  - Полный экран записи — `fullScreenCover` (`RootTabView.swift:178`), закрывается только кнопкой ⌄. Граббер на панели записи (`RecordingChrome.swift:110–113`) обещает жест, которого нет.
- **Why:** `tab-bars.md › Phone (iOS)`: "you can choose to minimize the tab bar and move the accessory inline with it when a person scrolls down." `sheets.md › Mobile (iOS, iPadOS)`: "A grabber shows people that they can drag the sheet to resize it; they can also tap it to cycle through the detents."
- **Fix:**
  ```swift
  .accessibilityElement(children: .ignore)
  .accessibilityLabel(Text("\(title), \(status)")).accessibilityAddTraits(.isButton)
  .accessibilityAction(open).accessibilityAction(named: Text(controlLabel), action)
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement   // .inline → одна строка
  ```
  Граббер либо убрать, либо сделать рабочим: `DragGesture` → `onMinimize()` плюс `.accessibilityAction(named: "Minimize")`.
- **Скриншоты:** `shell/summary-running`, `shell/recording`.

**K-5. Стекло в контенте: «Начать тренировку» на экране «Пульс» — Improvement · Medium**
- **What:** `Strand/Screens/LiveView.swift:411,421` — `.glassProminent` на кнопке внутри прокрутки. Других случаев стекла в контенте поиск не нашёл.
- **Why:** `liquid-glass.md › Review checklist`: "Glass on app backgrounds, cards, list rows, or content containers is a defect."
- **Fix:** `.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)`.
- **Скриншот:** `light/live` (низ экрана).

**K-6. «Уменьшить прозрачность»: градиент шапки Сводки срезан белой полосой — Improvement · Medium**
- **What:** при включённом режиме верхние ~110 pt (статус-бар и зона навигационной панели) становятся непрозрачно-белыми, и тёплый градиент Сводки начинается с жёсткого края под ними. Без режима градиент доходит до верха экрана.
- **Why:** `liquid-glass.md › Which variant`: "Both variants change appearance when people choose a preferred look for Liquid Glass in system settings, or turn on Reduce Transparency or Increase Contrast. Design so those states still read well instead of fighting them."
- **Fix:** продлить фон-градиент под safe area (`.ignoresSafeArea(edges: .top)` у фона в `SummaryGlass.swift`) и не ставить свой `toolbarBackground`. Сверить с Сводкой «Здоровья» при том же режиме.
- **Скриншоты:** `rt/shell-running` против `shell/summary-running`.

**K-7. Системные фоны зашиты hex-значениями, шторки в тёмной теме не приподнимаются — Improvement · Medium**
- **What:** `summaryCanvas`/`summaryCard` = `#F2F2F7/#000000` и `#FFFFFF/#1C1C1E` (`Palette.swift:332–334`), `settingsForm` (`SettingsView.swift:171–176`). В шторках тёмной темы холст остаётся `#000` вместо elevated, поэтому лист профиля сливается с подложкой. `PairingCard` заливает стекло шторки непрозрачным `#1C1C1E` (`AddDeviceWizard.swift:880`). Рядом живёт второй нейтральный набор `surfaceBase` `#F3F4F6/#1D1E23` (`RootTabView.swift:238, 273, 310, 330`).
- **Why:** `dark-mode.md › Mobile (iOS, iPadOS)`: "Prefer the system background colors. Dark Mode is dynamic, which means that the background color automatically changes from base to elevated when an interface is in the foreground, such as a popover or modal sheet."
- **Fix:** `Color(uiColor: .systemGroupedBackground)` / `.secondarySystemGroupedBackground`. `settingsForm()` свести к `formStyle(.grouped)`. `surfaceBase` удалить.
- **Скриншоты:** `dark/profile`, `dark/addwizard-confirm`.

**K-8. Шторки только для чтения закрываются подтверждающей ✓ — Improvement · Medium**
- **What:** «Больше данных о сне» (`SleepMoreDataView.swift:83–85`) и лист профиля закрываются синей ✓. Сохранять там нечего.
- **Why:** `sheets.md › Anatomy`: "The Cancel (or Close) button dismisses a sheet without saving any changes." / "The Done button dismisses a sheet after completing a task or explicitly saving changes."
- **Fix:** `ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }`.
- **Скриншоты:** `light/sleepmore`, `light/profile`.

**K-9. Повторное касание вкладки ещё и обновляет данные — Craft · Low**
- **What:** `RootTabView.swift:82`: `Task { await repo.refresh() }`.
- **Why:** `tab-bars.md › Best practices`: "Use a tab bar to support navigation, not to provide actions."
- **Fix:** удалить строку: обновление уже есть в `.refreshable` и при возврате в приложение.

**K-10. Граббер у шторок с одной высотой — Craft · Low**
- **What:** `StrandDesign/Components.swift:71–75`. WhatsNew, ScoringGuide и ещё 3 шторки показывают граббер, хотя детент у них один — `.large`.
- **Why:** `sheets.md › Mobile (iOS, iPadOS)`: "A grabber shows people that they can drag the sheet to resize it".
- **Fix:** `.presentationDragIndicator(largeFirst ? .hidden : .visible)`.

### 2. Сводка

**S-1. Заряд, Усилие и Отдых меняют цвет между экранами; один цвет значит разное — Improvement · High**
- **What:**
  - На Сводке Заряд красный (Move), Усилие зелёное (Exercise), Отдых голубой (Stand): `SummaryView.swift:228–253`.
  - На странице «Заряд» столбцы красно-жёлто-зелёные по порогам, заголовок подборки зелёный, «Последнее 46 %» красное, «Среднее 44 %» бирюзовое. У Усилия всё оранжевое: `MetricHealthStyle.swift:56–60, 80–84, 238–242`.
  - Карточка тренда Заряда на той же Сводке зелёная.
  - В зале зелёный означает «идёт подход», а в интервалах — «отдых» (`LiftSessionView.swift:14–17`, `IntervalTimerView.swift:96–100`, Live Activity `LiftLiveActivity.swift:76–78` против `IntervalLiveActivity.swift:56–58`).
  - Красное «46 %» стоит рядом с текстом «Последнее значение выше вашего среднего».
- **Why:** `color.md › Best practices`: "Avoid using the same color to mean different things." `charting-data.md › Designing effective charts`: "it’s important to use one chart type and consistent colors, annotations, layouts, and descriptive text to signal that the dataset remains the same."
- **Fix:**
  - Канон — цвета колец: в `MetricHealthStyle.tint` / `KeyMetric.healthTint` `.charge → activityMoveText`, `.effort → activityExerciseText`, `.rest → activityStandText`.
  - Состояние Заряда (низкий/средний/высокий) показывать шкалой только на столбцах, с подписью порогов (M-4).
  - Работа/отдых: одна пара для зала, интервалов и баннеров — работа `exercise`, отдых `rest`.
  - «Последнее» в подборке — цветом показателя, а не красным.
- **Скриншоты:** `light/summary` + `light/metric-charge` + `light/metric-strain`.

**S-2. Карточка «Активность» не перестраивается — Improvement · High**
- **What:** три колонки, два разделителя по 25 pt и кольца 64 pt в одном `HStack`, у колонки `.fixedSize()` (`SummaryCards.swift:127–173`, строка 170). Когда Заряд перенесён со вчера, подпись «Прошлой ночью · 24 сент.» (~150 pt) переполняет строку уже на стандартном кегле, а на AX1 — всегда.
- **Why:** `typography.md › Supporting Dynamic Type`: "When font size increases in a horizontally constrained context, inline items (like glyphs and timestamps) and container boundaries can crowd text and cause truncation or overlapping."
- **Fix:**
  ```swift
  ViewThatFits(in: .horizontal) {
      HStack { columns; Spacer(minLength: 10); rings }
      VStack(alignment: .leading, spacing: 12) { rings; columns }
  }
  ```
  В подписи колонки `.lineLimit(2)` вместо `.fixedSize()`.
- **Скриншоты:** `light/summary`, `ax/summary`.

**S-3. VoiceOver читает декоративные иконки и шевроны карточек — Improvement · Medium (по коду)**
- **What:** `SummaryCards.swift:65,80,112`: иконка категории и шеврон внутри `.combine` (218) озвучиваются именами символов. В проекте 20 `chevron.right`, и ни у одного нет `accessibilityHidden`.
- **Why:** `voiceover.md › Descriptions`: "Exclude purely decorative images from VoiceOver."
- **Fix:** `.accessibilityHidden(true)` на иконку и шеврон в `SummaryCardTitleRow`, `SleepMetricCards.swift:98`, `BreathingView.swift:365`.

**S-4. Мелочи Сводки — Craft · Low**
- **What:**
  - Усилие «0,0» без единицы, а в «Все показатели» — «0,0 /100».
  - Один глиф пламени обозначает Активность, Калории и Усилие.
  - «Закреплено» против «Закрепленное» у Apple.
  - Мини-график Калорий из двух точек выглядит как две розовые капсулы-переключатель.
  - «Показать все показатели» против «Показать все данные о здоровье» у Apple; sentence case в «Show all metrics» (`SummaryView.swift:347`) против «Show All Trends» (`:394`).
- **Why:** `writing.md › Best practices`: "Build language patterns." Один глиф на три понятия — суждение ревьюера.
- **Fix:** для Усилия — «/100» или ничего, одинаково везде; Калориям — `flame.fill`, Усилию — `bolt.heart` или `figure.run`; ru-строка «Закреплённое»; для 1–2 точек мини-график не рисовать.
- **Скриншоты:** `light/summary`, `light/explore`.

### 3. Сон и «Больше данных о сне»

**SL-1. Кольцо «Оценки сна»: четыре сегмента различаются только цветом — Improvement · High**
- **What:** `SleepHealthComponents.swift:47–55, 64–66`. Сегменты Длительность / Прерывания / Глубокий и REM / Регулярность рассчитаны (`SleepScore.Part.points`), но нигде не подписаны. VoiceOver слышит только «Оценка сна, 95». Владелец разбивку под кольцом убрал сознательно.
- **Why:** `color.md › Inclusive color`: "Avoid relying solely on color to differentiate between objects, indicate interactivity, or communicate essential information."
- **Fix:** визуально ничего не добавлять, озвучить разбивку:
  ```swift
  .accessibilityValue(Text(score.parts.map { "\($0.part.label) \($0.points ?? 0) из \($0.part.maxPoints)" }.joined(separator: ", ")))
  ```
  У Apple разбивка стоит под кольцом. Вернуть её — решение владельца, см. таблицу «не 1 в 1».
- **Скриншот:** `light/sleep`.

**SL-2. Цвета стадий сна означают на листе другие вещи — Improvement · High**
- **What:**
  - `SleepMoreDataView.swift:249–257`: голубая точка REM обозначает «Время в постели», синяя Core — «Время сна», цвет Deep — «Потребность».
  - `:595–596`: коралловый «Бодрствование» означает недобор.
  - `SleepPageCards.swift:77`: бирюзовая линия среднего, а в кольце бирюзовый — это сегмент «Глубокий и REM».
- **Why:** `color.md › Best practices`: "Use color consistently throughout your interface, especially when you use it to help communicate information like status or interactivity."
- **Fix:** у рядов «Количество» `dot: nil`; недосып цветом `textSecondary` со знаком ±; среднее в подборке — `textSecondary`, как у Apple.
- **Скриншот:** `light/sleepmore` → «Количество».

**SL-3. Подписи оси часов наезжают друг на друга — Improvement · Medium**
- **What:** на стандартном кегле последние метки сливаются в «09:0011:00» (`light/sleepmore`), на AX1 — все («17192021…», `ax/sleepmore`). Колонка часов фиксирована 40 pt со смещением −7 при масштабируемом `caption` (`SleepRangeChart.swift:20, 133, 152`), подписи рядов «Бодрствование/REM/Лёгкий/Глубокий» лежат прямо на графике.
- **Why:** `typography.md › Supporting Dynamic Type`: "Keep text truncation to a minimum as font size increases."
- **Fix:** оси на Swift Charts (`AxisMarks(values: .stride(by: .hour, count: dts.isAccessibilitySize ? 6 : 2))`); ширину колонки — через `@ScaledMetric`; подписи рядов — в `chartYAxis`.
- **Скриншоты:** `light/sleepmore`, `ax/sleepmore`.

**SL-4. «Выключенные» ряды отключены через `allowsHitTesting` — Improvement · Medium (по коду)**
- **What:** `SleepMoreDataView.swift:237` (стадии на «6М»), `:296` (сравнения, которые нельзя построить). Ряды не приглушены, и для VoiceOver остаются кнопками.
- **Why:** `lists-and-tables.md › Best practices`: "Provide appropriate feedback when people select a list item."
- **Fix:** `.disabled(range == .sixMonths)`, `.disabled(!row.plottable)`.

**SL-5. Стадии и пункты меню: «REM» без перевода, пункты меню не глаголы — Craft · Low**
- **What:** `Palette.swift:696–698` — `"REM"` захардкожен, хотя в каталоге есть «Быстрый сон». «Лёгкий» вместо Health-овского «Основной» даёт «Лёгкий, в среднем». Пункты меню ••• — «Отход ко сну» и «Я не сплю» (`SleepHealthView.swift:503–504`).
- **Why:** `menus.md › Labels`: "label a menu item that initiates an action using a verb or verb phrase that describes the action".
- **Fix:** `String(localized: "REM", bundle: .module)` → «Быстрый сон»; `.light` → «Основной»; меню — «Отметить отход ко сну» / «Отметить пробуждение».

**SL-6. Поясняющая проза на листе — Craft · Low**
- **What:** `SleepMoreDataView.swift:299–305, 612–615` — пояснения под сравнениями и недосыпом.
- **Why:** `writing.md › Getting started`: "Check each word to be sure it needs to be there."
- **Fix:** удалить оба `Text`.

### 4. Страница показателя, «Все показатели», Тренды

**M-1. ⓘ озвучивается «О приложении»; поповеры принудительно в компактной ширине — Improvement · Medium**
- **What:**
  - `MetricDetailView.swift:176`: `InfoButton(label: "About")` в ru озвучивается «О приложении».
  - `SummaryView.swift:303`, `SleepHealthView.swift:136`: `.presentationCompactAdaptation(.popover)` с фиксированной рамкой 320×360; календарь дня — самодельный поповер.
- **Why:** `popovers.md › Mobile (iOS, iPadOS)`: "Avoid displaying popovers in compact views." `pickers.md › Mobile (iOS, iPadOS)`: "Use a compact date picker when space is constrained."
- **Fix:** `InfoButton(label: "About \(metric.title)")`; для даты — `DatePicker("", selection: $day, displayedComponents: .date).datePickerStyle(.compact)` в заголовке пейджера.
- **Скриншот:** `light/metric-hrv`.

**M-2. Подписи осей третичным серым 3,94:1 — Improvement · Medium**
- **What:** `MetricHealthChart.swift:140–142`, `MetricStressDay.swift:104–106`, `SleepPageCards.swift:40–42`: `#7D808A` на `#FFFFFF`, 12 pt, фиксированный кегль.
- **Why:** `accessibility.md › Vision`: "Strive to meet color contrast minimum standards."
- **Fix:** `AxisValueLabel().foregroundStyle(StrandPalette.textSecondary)` (7,11:1).

**M-3. Пустое состояние — абзац без действия — Improvement · Medium**
- **What:** на «Шагах» без данных — «Нет данных» и 4 строки «Сначала импортируйте историю. Данные WHOOP из раздела «Источники данных»…» (`MetricDetailView.swift:301–306`), без кнопки. Путь описан словами.
- **Why:** `writing.md › Best practices`: "Provide clear next steps on any blank screens." и "If you need to direct someone to a setting, provide a direct link or button, rather than trying to describe its location."
- **Fix:** абзац удалить; в пустом состоянии одна кнопка:
  ```swift
  ContentUnavailableView { Label("No Data", systemImage: metric.icon) } actions: {
      NavigationLink("Import History", value: SettingsPage.dataSources)
  }
  ```
- **Скриншот:** `light/metric-steps`.

**M-4. Заряд: состояние на столбцах только цветом, жёлтый 1,51:1 — Improvement · Medium**
- **What:** `MetricHealthStyle.swift:82–83`: красный/жёлтый/зелёный по порогам 50/70 без линий и подписей. Жёлтый `#FFCC00` на белом даёт 1,51:1.
- **Why:** `charts.md › Color`: "Avoid relying solely on color to differentiate between different pieces of data or communicate essential information in a chart."
- **Fix:** `RuleMark(y: .value("", 50))` и `RuleMark(y: .value("", 70))` с `.annotation { Text("Low") }`; в строке выбора выводить слово состояния.
- **Скриншот:** `light/metric-charge`.

**M-5. Тренировочная нагрузка: линии различаются только цветом — Improvement · Medium**
- **What:** `TrainingLoadView.swift:125–155`: «Тренированность» и «Усталость» — две сплошные линии разного цвета. Легенда — цветные точки. Подпись для VoiceOver («хроническая против острой») не совпадает со словами на экране.
- **Why:** `charts.md › Color`: "One way to supplement color is to use different shapes or patterns to depict different parts of data."
- **Fix:** у «Усталости» `.lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 3]))`; `.accessibilityLabel("Fitness and Fatigue")`.
- **Скриншот:** `light/trainingload`.

**M-6. «Показатели без данных»: раскрытие без состояния — Improvement · Medium (по коду)**
- **What:** `AllMetricsView.swift:262–281` — кнопка-раскрывашка без `accessibilityValue`.
- **Why:** `voiceover.md › Navigation`: "Inform VoiceOver when visible content or layout changes occur."
- **Fix:** `DisclosureGroup(isExpanded: $showsEmpty)` или `.accessibilityValue(expanded ? "Expanded" : "Collapsed")`.

**M-7. Мелочи страниц показателей — Craft · Low**
- **What:**
  - Диапазон без «Д»: у Apple Д·Н·М·6М·Г.
  - Длинное тире в диапазоне дат «22—28 сент.»: у Apple короткое «22–28».
  - Единица «Δ°C» у температуры кожи — жаргон.
  - Значения на карточках Трендов («51,4», «76») лежат прямо на линии.
  - В тексте Fitness Age стоит «we can show» (`MetricDetailView.swift:531–536`).
- **Why:** `writing.md › Best practices`: "Avoid using we altogether because it may be unclear who the “we” in question refers to."
- **Fix:** добавить `.day` там, где есть внутридневные данные; даты форматировать через `Date.IntervalFormatStyle`; «+0,4 °C» с подписью «Отклонение»; подпись значения — `.annotation(position: .top)`; «we» убрать.
- **Скриншоты:** `light/metric-hrv`, `light/explore`, `light/trends`.

### 5. Тренировки: вкладка, «Все тренировки», детали, запись, зал, интервалы, дневник, ручное добавление, выбор спорта

**W-1. Тренировка удаляется полным свайпом без подтверждения и без undo — Improvement · High**
- **What:** в `WorkoutHistoryView.swift:70–74` у `.swipeActions` остаётся `allowsFullSwipe` по умолчанию. `delete` (`:160–164`) стирает и GPS-маршрут. Для сравнения: сессия зала удаляется с подтверждением (`LiftSessionDetailSheet.swift:155–161`), у сна есть «Отменить».
- **Why:** `alerts.md › Best practices`: "…when people take an uncommon destructive action that they can’t undo, it’s important to display an alert in case they initiated the action accidentally." `undo-and-redo.md › Best practices`: "People generally expect to initiate undo and redo in system-supported ways, such as … shaking their iPhone."
- **Fix:**
  ```swift
  .swipeActions(allowsFullSwipe: false) { … }
  @Environment(\.undoManager) private var undoManager
  undoManager?.registerUndo(withTarget: repo) { r in Task { await r.restoreWorkout(snapshot) } }
  undoManager?.setActionName(String(localized: "Delete Workout"))
  ```
  `restoreWorkout` сделать по образцу `undoDeleteSleepSession`.

**W-2. Шторки теряют ввод при смахивании и по ✕ — Improvement · High**
- **What:** `LiftProgramEditorSheet.swift:119`, `LiftProgramItemSheet.swift:139`, `LiftSessionEditSheet.swift:90` (флаг `hasChanges` отключает только ✓), `ManualWorkoutSheet.swift:156`, `LiftSetEditor.swift:111,121` (детент medium), `MarkerEditorView.swift:219–222` (Lab Book). В `Strand/Fitness` нет ни одного `interactiveDismissDisabled`.
- **Why:** `sheets.md › Mobile (iOS, iPadOS)`: "If people have unsaved changes in the sheet when they begin swiping to dismiss it, use an action sheet to let them confirm their action." `modality.md › Best practices`: "if closing the view could result in the loss of user-generated content, be sure to explain the situation and give people ways to resolve it."
- **Fix:**
  ```swift
  .interactiveDismissDisabled(hasChanges)
  SheetCloseButton { hasChanges ? (askDiscard = true) : dismiss() }
  .confirmationDialog("", isPresented: $askDiscard) {
      Button("Discard Changes", role: .destructive) { dismiss() }
      Button("Keep Editing", role: .cancel) {}
  }
  ```

**W-3. ✕ в интервалах сбрасывает прогресс без вопроса — Improvement · High**
- **What:** `IntervalTimerView.swift:209–212` сразу вызывает `runner.stopAndReset()`. Тот же ✕ при записи тренировки спрашивает подтверждение (`LiveWorkoutView.swift:71`).
- **Why:** `progress-indicators.md › Best practices`: "When canceling a process results in lost progress, it’s helpful to provide an alert that includes an option to confirm the cancellation or resume the process."
- **Fix:** `.confirmationDialog` с кнопкой «Завершить интервалы» (`.destructive`), когда `runner.elapsed > 0 && !runner.isFinished`.

**W-4. RPE вводится четырьмя разными способами, два без проверки — Improvement · Medium**
- **What:**
  - текстовое поле с плейсхолдером «7», который выглядит как введённое значение (`LiftSessionView.swift:465–470`, `:674`);
  - поле в правке (`LiftSessionEditSheet.swift:72–78`);
  - поле с проверкой (`LiftProgramItemSheet.swift:97–103`);
  - меню 5–10 (`LiftSetEditor.swift:85–90`).
  - При финише и в правке можно сохранить RPE 15.
- **Why:** `entering-data.md › Best practices`: "When possible, offer choices instead of requiring text entry." и "Dynamically validate field values."
- **Fix:** один компонент для всех четырёх мест:
  ```swift
  Picker("RPE", selection: $rpe) {
      Text(verbatim: "—").tag(Double?.none)
      ForEach(Array(stride(from: 1.0, through: 10.0, by: 0.5)), id: \.self) { Text(LiftFormat.trim($0)).tag(Double?.some($0)) }
  }
  ```
  В Fitness есть готовый образец: шкала «Лёгкая / Умеренная / Тяжёлая / На пределе».

**W-5. Состояние записи видно только по глифу; «Завершить» выглядит как «закрыть» — Improvement · Medium**
- **What:** на паузе меняется только центральная кнопка ‖→▶. Часы остаются зелёными, слова «Пауза» нет. «Завершить» — серый ✕, тот же глиф, что закрытие шторки (`RecordingChrome.swift:87–90, 144`). Заливка кнопки `white 0.2` на панели `white 0.11` даёт 1,35:1.
- **Why:** `feedback.md › Best practices`: "Consider integrating status feedback into your interface." `buttons.md › Role`: "a destructive button uses the system red color."
- **Fix:** на паузе `RecordingClockText(…, tint: paused ? StrandPalette.fitnessTime : StrandPalette.activityExerciseText)` + подпись «Пауза»; у «Завершить» — `tint: .red`, заливка `tint.opacity(0.25)`, как на Apple Watch.
- **Скриншот:** `shell/recording`.

**W-6. Undo в зале: непонятно, что отменится; работает только на одной странице — Improvement · Medium**
- **What:** кнопка подписана просто «Undo» (`LiftSessionView.swift:169–171`). Подход удаляется свайпом на странице 1 (`:245–251`), а кнопки Undo там нет. `UndoManager` не подключён, поэтому встряхивание не работает.
- **Why:** `undo-and-redo.md › Mobile (iOS, iPadOS)`: "Briefly and precisely describe the operation to be undone or redone."
- **Fix:** после каждой правки — `undoManager?.registerUndo(withTarget: session) { $0.undo() }` и `setActionName("Delete Set")`. Подпись кнопки брать из этого имени.

**W-7. Контекстные меню есть только в одном списке — Improvement · Medium**
- **What:** меню есть в «Все тренировки» (`WorkoutHistoryView.swift:138–158`). Их нет у недавних на вкладке (`WorkoutsHomeView.swift:101–113`), у карточек программ (`LiftLogView.swift:118–145`) и у истории сессий (`:324–336`). На детали тренировки в тулбаре только «Экспорт» (`WorkoutDetailView.swift:61–69`). У пункта «Label as…» нет иконки, хотя у соседних пунктов есть (`:140`).
- **Why:** `context-menus.md › Best practices`: "Support context menus consistently throughout your app." и "Always make context menu items available in the main interface, too." `menus.md › Icons`: "provide icons for all menu items in a group, or none of them."
- **Fix:** вынести `WorkoutRowMenu(row:)` и подключать через `.contextMenu { WorkoutRowMenu(row: row) }` везде. На детали — `Menu { WorkoutRowMenu(row: row) } label: { Image(systemName: "ellipsis") }.barGlyph()`.

**W-8. VoiceOver не слышит состояний и выбранного фильтра — Improvement · Medium (по коду)**
- **What:**
  - Подпись кнопки переключения страниц всегда «Sets» (`LiftSessionView.swift:423`).
  - У чипов фильтра нет `.isSelected`, их высота около 34 pt (`WorkoutHistoryView.swift:126–136`).
- **Why:** `accessibility.md › Mobility`: "To ensure a smooth experience, label interface elements appropriately."
- **Fix:** `.accessibilityValue(recorded ? "Done" : isWorking ? "In progress" : "")`, `.accessibilityAddTraits(selected ? .isSelected : [])`, `.frame(minHeight: 44)`.

**W-9. Reduce Motion не учитывается на экранах тренировок — Improvement · Medium (по коду)**
- **What:**
  - `numericText` каждую секунду и линейная полоса (`IntervalTimerView.swift:179, 187`);
  - сотые доли секунды обновляются 20 раз в секунду (`LiveWorkoutView.swift:146,164`, `LiftSessionView.swift:141,424`);
  - отсчёт 3-2-1 использует хаптик `.selection` (`IntervalTimerView.swift:243`).
- **Why:** `accessibility.md › Cognitive`: "When this setting is active, ensure your app or game responds by reducing automatic and repetitive animations, including zooming, scaling, and peripheral motion." `playing-haptics.md › Selection`: "Selection haptics provide feedback while the values of a UI element are changing."
- **Fix:** `.contentTransition(reduceMotion ? .identity : .numericText())`, `.animation(reduceMotion ? nil : .linear(duration: 1), value: …)`, для отсчёта `.impact(weight: .light)`.

**W-10. Экран гаснет по-разному на трёх экранах записи — Improvement · Medium**
- **What:** запись тренировки — по настройке, выключено по умолчанию (`LiveWorkoutView.swift:26,63`); интервалы — всегда (`IntervalTimerView.swift:233–235`); зал — никогда, и таймер отдыха гаснет вместе с экраном.
- **Why:** `accessibility.md` (вступление): "Your interface uses familiar and consistent interactions that make tasks straightforward to perform."
- **Fix:** один ключ `workoutKeepScreenOn` для всех трёх: `.onAppear { ScreenIdle.keepAwake(keepScreenOn) }` в `LiftSessionView` и `IntervalRunView`.

**W-11. Ошибки сохранения проглатываются, шторка закрывается как при успехе — Improvement · Medium (по коду)**
- **What:** `LiftSessionView.swift:676,694`, `LiftProgramEditorSheet.swift:236,255`, `LiftSessionEditSheet.swift:273–278`, `LiftSessionDetailSheet.swift:169` — `try?` без реакции.
- **Why:** `feedback.md › Best practices`: "Show people when a command can’t be carried out and help them understand why."
- **Fix:** `do { try await … } catch { saveFailed = true; return }` + `.alert("Couldn’t Save Session", isPresented: $saveFailed) { Button("OK") {} }`. При ошибке шторку не закрывать.

**W-12. Один глагол — одно действие; регистр — Improvement · Medium**
- **What:**
  - Для одного действия разные глаголы: «End Workout» / «Delete Workout», «Finish Session» / «Discard Session» / «Discard session», просто «End» (`LiveWorkoutView.swift:72,76`, `LiftSessionView.swift:407,413,489,503`, `IntervalTimerView.swift:209`).
  - Регистр смешан: «Add exercise», «Choose a workout», «Import a program»; «Sets per Muscle» рядом с «How hard it felt».
  - Ошибка «Enter a sport.» относится к полю, которое выбирают, а не вводят (`ManualWorkoutSheet.swift:264`).
  - Карточка «Силовая» запускает пульсовую тренировку, а сессия в Дневнике сохраняется как «Strength Training».
  - Прочерков три вида: «--», «—», «–».
  - Тире в диапазонах разные: «25-250 bpm» и «0–621 mi».
- **Why:** `writing.md › Best practices`: "Adopt capitalization rules that align with your app’s style, then apply them consistently." и "Give clear guidance and use consistent language throughout processes with multiple steps."
- **Fix:** словарь из трёх глаголов: Завершить — остановить запись; Отменить — выбросить несохранённое; Удалить — удалить сохранённое. Кнопки и заголовки в Title Case (en). Ошибка — «Выберите вид тренировки.». Прочерк один: «—».

**W-13. Проза, информационный алерт, пустые состояния без действия — Craft · Low**
- **What:**
  - Проза в подвалах: `LiftSessionExerciseSheet.swift:78`, `LiftExercisePicking.swift:128,206`, `LiftProgramItemSheet.swift:105`, `LiftLogView.swift:246`, `WorkoutDetailView.swift:309,335`, `LiftSessionDetailSheet.swift:288,504`, `LiftProgramImportSheet.swift:38,141`.
  - Информационный алерт с «OK» в роли cancel (`LiftSessionExerciseSheet.swift:63–69`).
  - Пустые состояния без кнопки: `WorkoutHistoryView.swift:93–95`, `LiftSessionView.swift:87–95`.
- **Why:** `alerts.md › Best practices`: "Avoid using an alert merely to provide information." `writing.md › Best practices`: "Provide clear next steps on any blank screens."
- **Fix:** подвалы удалить. Алерт → «Список упражнений заполнен» с кнопкой «Управлять упражнениями». Пустое состояние → `EmptyStateView(title: Text("No Workouts"), systemImage: "figure.run") { Button("Show All") { sportFilter = nil } }`.

**W-14. Карта маршрута — Craft · Low**
- **What:**
  - Интерактивная `MKMapView` стоит внутри `ScrollView`, и её жесты конфликтуют с прокруткой.
  - Обе метки — стандартные красные, хотя в шапке файла обещан зелёный старт (`WorkoutRouteMap.swift:12` против `:56–58`).
  - Линия янтарная (`:95`).
- **Why:** `maps.md › Custom information`: "Use annotations that match the visual style of your app."
- **Fix:** статичное превью (`MapSnapshotter`), по тапу — полноэкранная карта, как в Fitness. Старт — `.tint(.green)`, финиш — `.tint(.red)`, линия — цветом Усилия.

### 6. Будильник и расписание сна

**AL-1. Резервный будильник не пробивает режим «Сон» — Improvement · High**
- **What:**
  - Уведомление «Smart alarm / Time to wake up.» (`Strand/App/AppModel.swift:1594–1597`, зеркало — `:1527–1530`) уходит без `interruptionLevel`, то есть `.active`. В Фокусе «Сон» оно будет задержано.
  - Батарея при этом просит `.timeSensitive` (`BatteryNotifier.swift:143,174`): срочность расставлена наоборот.
  - В `NOOP.entitlements` нет `com.apple.developer.usernotifications.time-sensitive`, поэтому iOS понижает до `.active` и батарею.
  - Утром приходят два «Smart alarm» подряд: «Good morning.» (`:1513–1514`) и «Time to wake up.».
- **Why:** `managing-notifications.md › Best practices`: "Build trust by accurately representing the urgency of each notification." `notifications.md › Best practices`: "Avoid sending multiple notifications for the same thing, even if someone hasn't responded."
- **Fix:** на iOS 26 — AlarmKit: `AlarmManager.shared.schedule(id:configuration:)` с еженедельным расписанием плюс `NSAlarmKitUsageDescription`. Это системный будильник, как в «Часах», со «Стоп/Отложить» поверх Silent и Focus. Фолбэк — `content.interruptionLevel = .timeSensitive` плюс entitlement в `project.yml` у NOOPiOS. Второе уведомление не отправлять, если резервное уже ушло. Первичный будильник — вибрация браслета, поэтому это High, а не Critical.

**AL-2. «Изменить» у нескольких расписаний неразличимы; удаление без роли — Improvement · Medium**
- **What:** у каждой карточки подпись просто «Изменить» (`SleepScheduleComponents.swift:109–117`). «Удалить расписание» — обычная кнопка с красным текстом, без `role: .destructive` (`SleepScheduleEditor.swift:54–70`).
- **Why:** `voiceover.md › Descriptions`: "System-provided controls have generic labels by default, but you should provide more descriptive labels that convey your app’s functionality." `buttons.md › Role`: "Destructive. The button performs an action that can result in data destruction."
- **Fix:** `.accessibilityLabel("Edit \(SleepSchedule.weekdaySummary(Set(entry.days)))")`; `Button(role: .destructive) { … }`.
- **Скриншот:** `light/schedule`.

**AL-3. Заголовки редактора мельче, чем у Apple — Craft · Low**
- **What:** у Apple («Настройка первого расписания») «Активно по дням» и «Отход ко сну и пробуждение» — жирные заголовки секций. У нас второй — серый 15 pt, псевдозаголовок без `.isHeader` (`SleepScheduleEditor.swift:38–42`). Кружки дней по высоте 38 pt.
- **Why:** `layout.md › Visual hierarchy`: "Group related items to clearly express related information or functions."
- **Fix:** `SleepScheduleHeader` для обеих секций плюс `.accessibilityAddTraits(.isHeader)`; кружкам — `.frame(minHeight: 44)`.
- **Скриншот:** `light/scheduleedit` против `apple/iphaf56dceb4-1`.

### 7. Live / Пульс

**LV-1. Технические фразы в карточке проблемы — Improvement · Medium**
- **What:** `LiveView.swift:480–489`: «Connected, waiting for a streaming state.», «Standard HR mode (low bandwidth)».
- **Why:** `writing.md › Getting started`: "Choose simple, plain language and write with accessibility and localization in mind, avoiding jargon and gendered terminology."
- **Fix:** оставить одну фразу на состояние («Подключение…», «Пульс обновляется реже») без режимов протокола.

**LV-2. «Весь день по секундам»: английские форматы, «bpm», жесты без альтернативы — Improvement · Medium**
- **What:**
  - Даты «EEE d MMM» и «HH:mm» с `en_US_POSIX` (`FullDayChartView.swift:268–270, 588–590`), поэтому русский пользователь видит «Mon 27 Sep».
  - Единица — «61 bpm».
  - Сегмент «Во владении | Все».
  - Постоянная подсказка «Сведите пальцы… перетащите… удерживайте…»: зум и сдвиг только жестами (`OverviewHRChart.swift:641–655`).
- **Why:** `text-fields.md › Best practices`: "Don’t assume the actual presentation of data, however, as formatting can vary significantly based on people’s locale." `gestures.md › Custom gestures`: "Not the only way to perform an important action in your app or game".
- **Fix:** `.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.activeLocale))`; единица — «уд/мин»; `.accessibilityZoomAction` плюс пункты меню «Увеличить / Уменьшить»; подсказку убрать, оставить только «Сбросить» при зуме.
- **Скриншот:** `light/sheet-fullday`.

**LV-3. Замер ВСР заканчивается молча — Improvement · Medium (по коду)**
- **What:** через 60 с — ни хаптика, ни объявления VoiceOver (`HRVSnapshotView.swift:401–440`). Ошибка сохранения тихо возвращает «Сохранено» → «Сохранить» (`:458–475`). Карточка «Браслет не передаёт данные — подключите его на экране «Пульс»» описывает путь словами, без ссылки.
- **Why:** `feedback.md › Best practices`: "When it makes sense, confirm that a significant action or task has completed."
- **Fix:** `.sensoryFeedback(.success, trigger: phase) { _, n in n == .done }`, `AccessibilityNotification.Announcement(…)`, при ошибке — «Повторить»; в карточке — кнопка «Открыть устройства».
- **Скриншот:** `light/sheet-hrv`.

**LV-4. Сердце бьётся 60 раз в минуту при любом пульсе; цвет в обход токенов — Craft · Low**
- **What:** `LiveView.swift:230` (ритм анимации) и `:218` (`Color(red:…)`).
- **Why:** `motion.md › Best practices`: "Add motion purposefully, supporting the experience without overshadowing it."
- **Fix:** длительность удара `60 / bpm` (при Reduce Motion — статично, как сейчас); цвет — токен `healthHeart`.

### 8. Дыхание (Осознанность)

**BR-1. Итог сессии: ложная точность ВСР — Improvement · High**
- **What:** «ВСР +14% от начала · пик 58 мс» считается по сырому RMSSD на скользящих 30 интервалах без очистки от эктопических ударов (`BreathingView.swift:951–983, 830–834`). «Пик» — максимум шумного ряда. У Apple в итогах «Осознанности» только время и пульс.
- **Why:** `machine-learning.md › Private or public`: "As with critical app features, features that use sensitive data must prioritize accuracy and reliability."
- **Fix:** оставить «Время» и «Пульс». Если ВСР нужна — одно число из очищенного окна: `HRVAnalyzer.analyze(rawRR:…, maxRejectedFraction: HRVAnalyzer.defaultSpotMaxRejectedFraction).rmssd`.
- **Скриншот:** `light/breathe-summary`.

**BR-2. Недоступный режим: причина набрана тем же приглушённым цветом — Improvement · Medium**
- **What:** ряд «Спокойствие — Нужен подключённый браслет» целиком приглушён. Причина, то есть единственная полезная строка, нечитаема.
- **Why:** `feedback.md › Best practices`: "Show people when a command can’t be carried out and help them understand why."
- **Fix:** приглушать только название и ▶, причину набирать `textSecondary`; по тапу открывать «Устройства».
- **Скриншот:** `light/breathe`.

**BR-3. Проверка стресса: три действия и два акцента — Improvement · Medium**
- **What:** в шторке «Дышать сейчас» (бирюзовая капсула), «Выключить» (серый текст, выглядит неактивным) и «Не сейчас» (синий).
- **Why:** `liquid-glass.md › Color on glass`: "Refrain from adding color to the background of multiple controls." `alerts.md › Buttons`: "Always use “Cancel” to title a button that cancels the alert’s action."
- **Fix:** одна основная кнопка «Дышать» (`.glassProminent`) и одна вторичная «Не сейчас». «Выключить проверки» — пункт в Настройках → Уведомления, не здесь.
- **Скриншот:** `light/breathe-stress`.

**BR-4. Полноэкранная сессия — Craft · Low**
- **What:** статус-бар и индикатор Home видны. Фраза «Вдох/Выдох» меняется без `.updatesFrequently`. ⌄ и ✕ — тёмно-серые круги, а не стекло (`RecordingChrome.swift:90`). «Готово» в итогах — самодельная капсула (`BreathingView.swift:532–541`). Тумблер «Звуковые подсказки» синий, в остальных местах тумблеры зелёные.
- **Why:** `going-full-screen.md › Best practices`: "Prioritize content by temporarily hiding toolbars and navigation controls."
- **Fix:** `.statusBarHidden(true).persistentSystemOverlays(.hidden)`; кнопки — `.buttonStyle(.glass)`, «Готово» — `.glassProminent`; тумблер — без `tint`.
- **Скриншоты:** `light/breathe-session`, `light/breathe-summary`.

### 9. ИИ-тренер (Коуч)

(Critical: CR-10 — отправка данных без вопроса, CR-12 — голосовой ввод.)

**CO-1. Нет раскрытия ИИ, «Доставлено» появляется по таймеру — Improvement · High**
- **What:** экран — чат с «контактом»: «печатает…», статусы доставки. Название «ИИ-тренер» раскрывает ИИ частично, но нигде не сказано, что ответы могут быть ошибочны, хотя речь о ВСР и нагрузке. «Доставлено» ставится через 1 с независимо от сети (`CoachView.swift:340–348, 739–742`).
- **Why:** `generative-ai.md › Transparency`: "Never trick someone into thinking they’re interacting with or viewing content authored by a human if they’re actually interacting with AI." `generative-ai.md › Inputs`: "it’s important to clearly communicate that AI-generated content may contain errors."
- **Fix:** без новых элементов: вторая строка `serviceLine` (на месте «iMessage · Encrypted» у Apple) → «ИИ · может ошибаться». «Доставлено» убрать, оставить только «Не доставлено».
- **Скриншот:** `light/coach`.

**CO-2. Нельзя остановить генерацию или повторить ответ — Improvement · High**
- **What:** пока идёт стрим, отправка и микрофон заблокированы, «стоп» нет. У ответа есть «Копировать», «Поделиться» и «Сохранить», но нет «Повторить» (`CoachView.swift:435–449, 672–674`; `AICoach.swift:722–753`).
- **Why:** `generative-ai.md › Outputs`: "surfacing controls like Edit, Undo, Retry, or Adjust near generated content preserves people’s agency"
- **Fix:**
  ```swift
  if coach.sending { Button { coach.stop() } label: { Image(systemName: "stop.fill") }.accessibilityLabel("Stop") }
  Button { regenerate() } label: { Label("Try Again", systemImage: "arrow.clockwise") }   // в contextMenu последнего ответа
  ```
- **Скриншот:** `light/coach-typing`.

**CO-3. «Отключить» стирает ключ и переписку без подтверждения — Improvement · High**
- **What:** удаляет ключ из Keychain и все сообщения одним касанием (`CoachSettingsView.swift:51–54`; `AICoach.swift:431–446`). Менее разрушительное «Очистить разговор» при этом подтверждение спрашивает.
- **Why:** `alerts.md › Best practices`: "…when people take an uncommon destructive action that they can’t undo, it’s important to display an alert in case they initiated the action accidentally."
- **Fix:** `.confirmationDialog("Disconnect \(coach.provider.displayName)?", …) { Button("Disconnect", role: .destructive) { coach.disconnect() } }`.
- **Скриншот:** `light/coach-settings`.

**CO-4. Ошибки ИИ: английские строки, HTTP-коды, служебный текст в сообщениях — Improvement · Medium**
- **What:**
  - Ошибки вида «The provider returned an error (503) - …», «Network problem: …» (`AICoach.swift:132–157, 804, 818, 842`) показываются 11 pt.
  - `*(stream interrupted)*` и «Today's brief» вшиты прямо в текст сообщения.
- **Why:** `writing.md › Best practices`: "Write clear error messages. … avoid blame, and be clear about what someone can do to fix it."
- **Fix:** `case .network: String(localized: "Can’t reach the provider. Check your connection and try again.")`; для 5xx — «Провайдер не отвечает. Повторите позже.»; служебные метки — полем модели, а не текстом.
- **Скриншот:** `light/coach-error`.

**CO-5. Настройки Коуча: жаргон и кнопка, похожая на поле — Improvement · Medium**
- **What:** «Провайдер — Custom (OpenAI-compatible)», «Заголовок ключа — Bearer». «Сохранить ключ» — серый текст в белой капсуле, выглядит как неактивное поле ввода.
- **Why:** `writing.md › Getting started`: "Choose simple, plain language and write with accessibility and localization in mind, avoiding jargon and gendered terminology." `buttons.md › Content`: "Ensure that each button clearly communicates its purpose."
- **Fix:** «Свой сервер»; «Заголовок ключа» спрятать в «Дополнительно»; «Сохранить ключ» — ряд-кнопка, серым только когда поле пустое, либо сохранять при `onSubmit` без кнопки.
- **Скриншот:** `light/coach-settings`.

**CO-6. Один хаптик на успех и сбой; ответ не объявляется — Improvement · Medium (по коду)**
- **What:** лёгкий impact на любой переход `sending → false`, в том числе при ошибке (`CoachView.swift:143–148`). VoiceOver о пришедшем ответе не узнаёт.
- **Why:** `playing-haptics.md › Best practices`: "If you use the same haptic pattern for a positive outcome like a level completion, people will be confused." `voiceover.md › Navigation`: "Inform VoiceOver when visible content or layout changes occur."
- **Fix:** `.sensoryFeedback(trigger: replyArrived) { _, _ in coach.errorText == nil ? .impact(weight: .light) : .error }`; `AccessibilityNotification.Announcement(…)`.

**CO-7. Мелочи чата — Craft · Low**
- **What:** «+» открывает подсказки (в «Сообщениях» это меню приложений) и дублирует ряд подсказок. Шестерёнка и тап по шапке ведут в одно место. Шапка поднята хаком `-54` (`CoachView.swift:201, 209`). В пустом чате подсказка уходит за правый край.
- **Why:** `design-principles.md › Simplicity`: "Include just what’s necessary."
- **Fix:** оставить один вход в настройки — тап по шапке, как в «Сообщениях»; «+» убрать; подсказкам дать `.scrollTargetBehavior(.viewAligned)` с видимым краем.
- **Скриншот:** `light/coach-empty`.

### 10. Журнал

**JR-1. «Да/Нет» различаются только заливкой, белое на бирюзе 2,57:1 — Improvement · Medium**
- **What:** `JournalView.swift:487–508`. VoiceOver слышит «Yes, button» без названия привычки и без состояния. Заполненность дня в полосе недели не озвучивается (`:143–145`).
- **Why:** `accessibility.md › Vision`: "Convey information with more than color alone."
- **Fix:**
  ```swift
  Picker(item.display, selection: answerBinding(item)) { Text("Yes").tag(Bool?.some(true)); Text("No").tag(Bool?.some(false)) }
      .pickerStyle(.segmented).fixedSize()
  ```
  Для колонки дня — `.accessibilityValue(Text(fraction.formatted(.percent)))`.

**JR-2. Удаление без undo; настроение не удалить — Improvement · Medium**
- **What:** записи удаляются сразу (`JournalView.swift:278–281, 298–300`); у настроения `remove: nil` (`:340–344`).
- **Why:** `undo-and-redo.md › Best practices`: "People generally expect to initiate undo and redo in system-supported ways, such as … shaking their iPhone."
- **Fix:** `undoManager?.registerUndo(withTarget: repo) { … }` (встряхивание, без нового UI); `remove: { moods[day] = nil; … }`.

**JR-3. Два «+» на одно действие; иконка 9 pt — Craft · Low**
- **What:** «+» в тулбаре (`:79–83`) и «+» у каждой строки (`:157–173`). Иконка 9 pt (`:127`). В целом экран близок к «Лекарствам» Apple, в том числе бирюзовые строки «Внесение» и полоса недели.
- **Why:** `design-principles.md` (вступление, Simplicity): "A well-designed experience removes the unnecessary, with every element earning its place."
- **Fix:** тулбарный «+» убрать или оставить только его, как у Apple («Добавить лекарство» в тулбаре, «+» у строки — для записи приёма; решить, что из этого что). Иконку — `.caption2`.
- **Скриншот:** `light/journal` против `apple/iph811670c81-1`.

### 11. «Что вами движет»

**WM-1. Вопросы на английском в русском интерфейсе — Improvement · High**
- **What:** «Did you drink any alcohol?», «Did you feel stressed?», «Did you have caffeine late in the day?» — это ключи вопросов из экспорта WHOOP (`Strand/Data/JournalCatalog.swift:32`), и они показываются как есть. В `Localizable.xcstrings` таких ключей нет.
- **Why:** `writing.md › Getting started`: "Choose simple, plain language and write with accessibility and localization in mind".
- **Fix:** хранить английский ключ, а показывать `JournalCatalog.displayName(for:)` → `String(localized:)`. Так же в Журнале и в подборках.
- **Скриншот:** `light/insights`.

**WM-2. Причинные формулировки и статистика на карточках — Improvement · High**
- **What:**
  - «Каждый напиток снижает Заряд на следующий день на ~5 %», «Tomorrow’s Charge 63%» — причинность и точный прогноз (`InsightsHubView.swift:641–655`).
  - Карточка показывается, даже когда кривая почти целиком популяционная.
  - «r = +0.42» на карточках, «d = 0.43» в деталях (`:147, 305, 336–349`).
  - Lab Book делает вывод по 4 точкам, «r = +0.62 · n = 4» (`LabBookView.swift:496, 674`).
- **Why:** `machine-learning.md › Confidence`: "When you know that confidence values correspond to result quality, you generally want to avoid showing results when confidence is low." `machine-learning.md › Attribution`: "In most situations, using percentages, statistics, and other technical jargon doesn’t help people assess the results you provide."
- **Fix:** `ForEach(model.doseCards.filter { !$0.response.priorDominated })`; текст «Заряд на следующий день обычно ниже…»; r и d убрать; прогноз убрать; порог выборки Lab Book — 8.
- **Скриншот:** `light/insights`.

**WM-3. Сегменты «Заряд · HRV · Отдых · RHR» — Improvement · Medium**
- **What:** русские слова вперемешку с английскими аббревиатурами. На Сводке тот же показатель называется «ВСР».
- **Why:** `writing.md › Getting started`: "Create a list of common terms, and reference that list to keep your language consistent."
- **Fix:** «Заряд · ВСР · Отдых · Пульс покоя» (или короткое «Пульс»).
- **Скриншот:** `light/insights`.

**WM-4. Пустое состояние «Пока нет закономерностей» без кнопки — Craft · Low**
- **What:** `InsightsHubView.swift:38–39`.
- **Why:** `writing.md › Best practices`: "Provide clear next steps on any blank screens."
- **Fix:** `ContentUnavailableView { … } actions: { Button("Open Journal") { … } }`.

### 12. Lab Book (Лабораторный журнал)

**LB-1. Единицы и числа по-английски — Improvement · Medium**
- **What:**
  - Единицы «nmol/L», «mmol/L», «µg/L», «mmHg» — у Apple «нмоль/л», «ммоль/л», «мкг/л», «мм рт. ст.».
  - Значения всегда через точку: «5.0», «1.40» (`LabBookView.swift:569–585`), а в остальном приложении запятая («14,0»).
  - Постоянный дисклеймер-футер (`:63`).
- **Why:** `text-fields.md › Best practices`: "Don’t assume the actual presentation of data, however, as formatting can vary significantly based on people’s locale."
- **Fix:** отдельный форматтер только для отображения (`plain` не трогать — на нём тесты паритета); единицы — `String(localized:)`; дисклеймер — в ⓘ.
- **Скриншот:** `light/labbook`.

**LB-2. Ввод анализа без проверки, удаление без подтверждения — Improvement · Medium**
- **What:** принимаются систолическое 1200 и давление 80/120; ✓ просто серая, без причины (`MarkerEditorView.swift:72–79, 176–197`). Анализ удаляется свайпом сразу (`LabBookView.swift:421–430`).
- **Why:** `entering-data.md › Best practices`: "Dynamically validate field values." `alerts.md › Best practices` (см. W-1).
- **Fix:** строка ошибки только при ошибке: `if s <= d { Text("Систолическое выше диастолического.").foregroundStyle(.red) }`; `.confirmationDialog("Удалить значение?")`.
- **Скриншот:** `light/labbookadd`.

**LB-3. Название рядом с «Журналом» — Craft · Low**
- **What:** в «Обзоре» «Журнал» и «Лабораторный журнал» стоят в одной карточке. У Apple раздел называется «Результаты анализов».
- **Why:** `writing.md › Best practices`: "Build language patterns."
- **Fix:** переименовать в «Анализы».
- **Скриншот:** `shell/browse`.

### 13. Настройки и Профиль

**ST-1. Своя настройка «Светлая/Тёмная/Автоматически» — Improvement · High**
- **What:** страница «Оформление» (`SettingsGeneralPages.swift:141–156, 229–256`) дословно копирует верх системного «Экран и яркость». Выбор применяется через `.preferredColorScheme` (`StrandiOSApp.swift:243`) и повторно в окне HUD, где стиль запоминается один раз при создании (`ConfirmationHUD.swift:61–67`). «Автоматически» в iOS — это расписание «закат/рассвет», а здесь — «как в системе»: подпись та же, смысл другой.
- **Why:** `dark-mode.md › Best practices`: "Avoid offering an app-specific appearance setting." … "Worse, they may think your app is broken because it doesn’t respond to their systemwide appearance choice."
- **Fix:** секцию «Внешний вид» и `.preferredColorScheme` убрать из релиза, один раз вызвать `UserDefaults.standard.removeObject(forKey: AppearanceMode.storageKey)`. Для скриншотов оставить `-theme.appearance` под `#if DEBUG`. Компромисс: владелец сам оставил выбор «Системная / Светлая / Тёмная». Если выбор остаётся, подпись «Автоматически» заменить на «Как в системе».
- **Скриншот:** `light/set-display` против `apple/iphd6804774e-1`.

**ST-2. Настройки вложены в лист профиля и повторяют его — Improvement · High**
- **What:** путь такой: аватар → лист (фото, имя, «Сведения о здоровье», «Устройства», «Импорт», «Настройки») → «Настройки».
  - На странице «Настройки» снова фото и имя (96 pt против 90 в листе), снова «Сведения о здоровье», браслет (он же «Устройства») и «Импорт»: три из четырёх рядов повторяются уровнем ниже (`ProfileDetailsView.swift:17–58`, `SettingsView.swift:26–122`).
  - До «Единиц» 4 уровня.
  - В «Здоровье» и Fitness лист аватара сам и есть настройки.
- **Why:** `settings.md › Best practices`: "Make settings available in ways people expect." и "too many settings can make the experience feel less approachable, while also making it hard to find a particular setting."
- **Fix:** лист = корень настроек:
  ```swift
  struct ProfileSheet: View { let onClose: () -> Void
      var body: some View { NavigationStack { SettingsView()
          .toolbar { ToolbarItem(placement: .confirmationAction) { SheetConfirmButton(action: onClose) } }
          .settingsDestinations() } } }
  ```
  `case .settings` удалить.
- **Скриншоты:** `light/profile`, `light/settings`.

**ST-3. «Импорт из файла…» заменяет всю базу без подтверждения — Improvement · High**
- **What:** после выбора файла база перезаписывается сразу (`BackupSyncView.swift:84, 135–141` → `DataBackup.swift:351–384`). «Восстановить…» с тем же результатом закрыт алертом «Replace all data» (`:114–122`).
- **Why:** `alerts.md › Best practices`: "…when people take an uncommon destructive action that they can’t undo, it’s important to display an alert in case they initiated the action accidentally."
- **Fix:** `.alert("Replace All Data?", isPresented: $confirmImport) { Button("Cancel", role: .cancel) {}; Button("Replace", role: .destructive) { runImport() } }`.
- **Скриншот:** `light/set-backup`.

**ST-4. Копии системных настроек: язык, «Уменьшить движение», 24-часовой формат, «Скрывать панель» — Improvement · Medium**
- **What:**
  - «Язык» (`AppLanguage.swift:10–19`, `SettingsGeneralPages.swift:28–39`) дублирует системное «Настройки → NOOP → Язык». В списке нет русского и zh-Hant, хотя переводы есть, и нужен перезапуск.
  - «Уменьшить движение» (`:170`) звучит как системная настройка, но действует только внутри NOOP (с системной складывается через `NoopMotion.swift:233`).
  - «Часы» (`:43–49`) повторяют системный 24-часовой формат.
  - «Скрывать панель при прокрутке» (`:172–174`) выносит в настройку механику iOS 26.
- **Why:** `settings.md › Best practices`: "Including custom versions of global options in your settings area is likely to confuse people because it implies that systemwide settings may not apply to your app or game". `settings.md › System settings`: "consider providing a button that opens it directly from your interface."
- **Fix:** ряд «Язык» со значением, который открывает `UIApplication.openSettingsURLString`. Три тумблера удалить: движение брать из `@Environment(\.accessibilityReduceMotion)`, формат — из `Locale`. После ST-1 «Значок приложения» перенести в «Основные», страницу «Оформление» удалить.
- **Скриншоты:** `light/set-general`, `light/set-display`.

**ST-5. «Заряд» — одновременно показатель и батарея; другие расхождения терминов — Improvement · Medium**
- **What:**
  - В «Уведомлениях» стоят «Заряд браслета» (батарея) и «Прогноз заряда» (показатель Заряд).
  - Ряд браслета в корне пишет «Подключено · 82%», а «Устройства» — «Подключено · без пары» или «Переподключение…»; «82%» против «82 %» (`SettingsView.swift:91–107` против `DeviceReadout.swift:44–66`).
  - `nonbinary` показан как «Другое» в онбординге и как «Небинарный» в «Сведениях о здоровье».
  - «Измерения тела» против «Параметры тела».
  - «Хранить копий» (`BackupSyncView.swift:64`).
  - «Импорт временных файлов» (`StorageSections.swift:27`) читается как действие.
  - Shortcuts переведено трижды: «Быстрые команды», «Команда», «Команд».
  - Заголовок «Apple Здоровье» против кнопки «Включить Apple Health» (у Apple приложение — «Здоровье»).
  - «Температура кожи — Температура» — непонятное значение.
- **Why:** `writing.md › Getting started`: "Create a list of common terms, and reference that list to keep your language consistent." `writing.md › Best practices`: "Consistency builds familiarity, helping your app feel cohesive, intuitive, and thoughtfully designed."
- **Fix:** батарея → «Батарея браслета»; строку статуса брать из `DeviceReadout.make(…).statusLine`; ru-правки: «Хранить копии», «Временные файлы импорта», «Здоровье», «Как у температуры». Пол — «Женский / Мужской / Другой», как в «Здоровье».
- **Скриншоты:** `light/set-notifications`, `light/set-applehealth`, `light/set-units`.

**ST-6. Информационные алерты и неверные имена кнопок — Improvement · Medium**
- **What:** алерт велит нажать «Use NOOP's own folder», а кнопка называется «NOOP folder» (`BackupSyncView.swift:42` против `:220`). «Используется папка NOOP» и «Восстановлено» — алерты с одной кнопкой OK (`:233–235, 281–282`). У одного действия три имени: «Сбросить норму» → диалог «Перекалибровать…» → «recalibrating» (`SettingsFeaturePages.swift:114, 126–137`).
- **Why:** `alerts.md › Content`: "refer to a button using its exact title without quotes." `alerts.md › Best practices`: "Avoid using an alert merely to provide information."
- **Fix:** одно имя действия; итог — `Confirmation.shared.show(String(localized: "Baseline reset"))`, как уже сделано для «Backed up».
- **Скриншот:** `light/set-scores`.

**ST-7. Запрещённое разрешение описано текстом, а не ссылкой — Improvement · Medium**
- **What:**
  - При запрещённых в iOS уведомлениях тумблеры включаются и молча ничего не делают (`NotificationsSettingsPage.swift:33–57`, `BatteryNotifier.swift:184`).
  - При `.denied` кнопка «Включить Apple Health» снова вызывает HealthKit, и шторка не появляется (`AppleHealthView.swift:69–81, 138–139`).
  - Apple Watch: «Allow Apple Health access» перед системным запросом; при отказе кнопка мёртвая (`AppleWatchSetupView.swift:113–137, 175`).
- **Why:** `writing.md › Best practices`: "If you need to direct someone to a setting, provide a direct link or button, rather than trying to describe its location." `privacy.md › Pre-alert screens, windows, or views`: "Use a term like “Continue” or “Next” to title the single button in your custom screen or window, clarifying that its action is to open the system alert."
- **Fix:** при `.denied` — `Button { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) } label: { LabeledContent("Notifications", value: String(localized: "Off")) }`; для Health и Watch — «Открыть Настройки»; до запроса — «Продолжить».
- **Скриншоты:** `light/set-notifications`, `light/sheet-watch`.

**ST-8. Текстовые поля: клавиатура, автокоррекция, пустые значения — Improvement · Medium**
- **What:**
  - Имя быстрой команды портится автокоррекцией (`ShortcutsSettingsPage.swift:49–53`).
  - У имени устройства нет кнопки очистки, и сохраняется пустая строка (`DeviceDetailView.swift:424–438`).
  - Hex-ключ Oura вводится на клавиатуре по умолчанию, ошибка «That is not a 32-character hex key.» (`AddDeviceWizard.swift:524–533`).
  - «Переименовать» стоит в одном ряду Form с полем и без подтверждения перезагружает браслет (`DeveloperSettingsPage.swift:91–103`).
- **Why:** `virtual-keyboards.md › Best practices`: "Choose a keyboard that matches the type of content people are editing." `text-fields.md › Mobile (iOS, iPadOS)`: "Display a Clear button in the trailing end of a text field to help people erase their input."
- **Fix:** `.autocorrectionDisabled().textInputAutocapitalization(.never)`; `.keyboardType(.asciiCapable)` плюс ошибка «Введите 32 символа: 0–9, a–f.»; `guard !draft.trimmingCharacters(in: .whitespaces).isEmpty`; у «Переименовать» — `.buttonStyle(.borderless)` и алерт «Переименовать и перезапустить браслет?».

**ST-9. Раздел «Разработчик» виден всем; внутри английский — Craft · Low**
- **What:** «Тестовые режимы: Sleep & Rest, Connection & Sync…» набраны verbatim-строками, хотя в каталоге есть «Сон и отдых». В корне настроек около 1000 строк переключателей протокола.
- **Why:** `settings.md › Best practices`: "too many settings can make the experience feel less approachable, while also making it hard to find a particular setting."
- **Fix:** раздел показывать после 7 касаний по версии в «О NOOP» (или под `#if DEBUG`); названия доменов — `String(localized:)`.
- **Скриншот:** `light/set-developer`.

**ST-10. Проза и повторы — Craft · Low**
- **What:**
  - Остались футеры: `SettingsGeneralPages.swift:38`, `StepsCalibrationSheet.swift:252`, `BackupSyncView.swift:75`.
  - Длинные алерты: `BackupSyncView.swift:174, 178, 220, 234`.
  - Аватар в четырёх размерах: 90 / 96 / 110 / 82.
  - «Точка + текст» как строка статуса в четырёх местах вместо серого значения.
  - Шевроны нарисованы вручную четырьмя способами.
  - Ряды «Двойное нажатие — Вибрация в ответ (подтверждение)» и «Экспортировать необработанные данные датчиков (CSV)» переносятся на 2 строки.
- **Why:** `lists-and-tables.md › Content`: "Keep item text succinct so row content is comfortable to read."
- **Fix:** удалить футеры; `LabeledContent` вместо «точки + текста»; `NavigationLink` вместо ручных шевронов; значения «Подтверждение», «Экспорт сырых данных (CSV)».

### 14. Устройства и мастер добавления

**DV-1. ⓘ в рядах устройств — картинка, а тап по ряду открывает страницу — Improvement · High**
- **What:** `DevicesView.swift:126–163`: ряд — скрытый `NavigationLink` (`.opacity(0)`), а ⓘ скрыт от VoiceOver и ничего не делает. В «Все часы» и Bluetooth тап по ряду переключает или подключает устройство, а ⓘ открывает детали. Смену активного браслета мы спрятали за страницу и алерт (`DeviceDetailView.swift:80–84`).
- **Why:** `lists-and-tables.md › Mobile (iOS, iPadOS, visionOS)`: "Use an info button only to reveal more information about a row’s content." … "If you need to let people drill into a list or table row’s subviews, use a disclosure indicator accessory control."
- **Fix:**
  ```swift
  Button { registry.setActive(device.id) } label: { rowContent }.buttonStyle(.plain)
      .overlay(alignment: .trailing) {
          Button { detail = DeviceRoute(id: device.id) } label: { Image(systemName: "info.circle") }
              .buttonStyle(.borderless).accessibilityLabel(Text("Details"))
      }
  ```
  Или оставить переход по тапу, но вместо ⓘ поставить системный шеврон.
- **Скриншот:** `light/devices`.

**DV-2. Поиск BLE не называет настоящую причину и винит браслет — Improvement · High**
- **What:**
  - При выключенном или запрещённом Bluetooth мастер бесконечно показывает «Поиск…» и спрашивает, «не спит ли устройство» (`AddDeviceWizard.swift:955–986`). Причина лежит в `live.lastSyncError` и не читается.
  - Онбординг через 12 с пишет «Не найден. Наденьте и зарядите браслет…» (`OnboardingWizard.swift:390–411`).
  - Каждый тап ставит новый `asyncAfter(12)` без отмены.
- **Why:** `writing.md › Best practices`: "display it as close to the problem as possible, avoid blame, and be clear about what someone can do to fix it."
- **Fix:** `if CBManager.authorization == .denied { Button("Open Settings") { … } } else if let err = live.lastSyncError { Text(err) }`; таймаут делать отменяемой `Task`.
- **Скриншот:** `light/addwizard-pick`.

**DV-3. «Импорт из файла» в мастере Oura просто закрывает мастер — Improvement · High**
- **What:** `AddDeviceWizard.swift:496, 558–561, 597, 1085` — `stopAllScans(); onClose()`. Импорта нет.
- **Why:** `buttons.md › Content`: "Ensure that each button clearly communicates its purpose."
- **Fix:** `NavigationLink("Import a File") { DataSourcesView() }`.

**DV-4. «Забыть», «Удалить данные», «Убрать из списка» — центральные алерты, имена путают — Improvement · Medium**
- **What:**
  - Все три действия подтверждаются алертом, а в Bluetooth и на странице AirPods iOS использует action sheet снизу (`DeviceDetailView.swift:240–249, 356–409`).
  - «Убрать из списка» тоже удаляет данные.
  - Обратимое «Сделать активным» тоже идёт через алерт.
- **Why:** `action-sheets.md › Best practices`: "Use an action sheet — not an alert — to offer choices related to an intentional action." `alerts.md › Best practices`: "Avoid displaying alerts for common, undoable actions, even when they’re destructive."
- **Fix:** `.confirmationDialog(title, isPresented: …, titleVisibility: .visible) { Button(actionTitle, role: .destructive) { … } }`; «Убрать из списка» → «Удалить устройство и данные»; «Сделать активным» — без подтверждения.

**DV-5. Мастер: самодельный «назад», «Подключить» открывает алерт, отмена называется не «Отменить» — Improvement · Medium**
- **What:**
  - Шаги переключаются через `@State` без push: «‹» нарисован вручную, свайпа назад нет (`AddDeviceWizard.swift:183–210`).
  - «Подключить» открывает алерт «Сделать активным?» с «Не сейчас» (`:459`).
  - Отмена выбора называется «Не оставлять ни одного активным» (`DevicesView.swift:108–113`).
  - Шаг подтверждения показан второй шторкой поверх «Устройств». Поле «Имя» — серая капсула с центрированным плейсхолдером, похожая на неактивную кнопку.
- **Why:** `alerts.md › Buttons`: "Always use “Cancel” to title a button that cancels the alert’s action." `alerts.md › Best practices`: "Use alerts sparingly."
- **Fix:** `NavigationStack(path: $steps)` + `.navigationDestination(for: Step.self)`; «Подключить» → `finishAdd(makeActive: true)`; `Button("Cancel", role: .cancel)`; имя — обычный `TextField` в `Form` с меткой.
- **Скриншот:** `light/addwizard-confirm`.

### 15. Онбординг и первый запуск

**ON-1. Системный запрос Bluetooth появляется в первую секунду, поверх экрана условий — Improvement · High**
- **What:** цепочка вызовов: `StrandiOSApp.swift:86` (`AppModel()` в `init`) → `AppModel.swift:252` (`BLEManager(...)`) → `BLEManager.swift:1370` (`CBCentralManager(...)` в `init`). Шаг «Наденьте браслет» говорит «Дальше попросим Bluetooth» (`OnboardingWizard.swift:303`), хотя вопрос уже задан.
- **Why:** `onboarding.md › Additional requests`: "making the request during your onboarding flow gives you the opportunity to show people why your app or game needs their permission and the benefits of granting it."
- **Fix:** создавать central сразу только если `CBManager.authorization != .notDetermined`, иначе — `makeCentralIfNeeded()` из шага сканирования. `central` сейчас `CBCentralManager!`, все обращения нужно перевести на guard. По правилам AGENTS.md это путь BLE: проверить на браслете.
- **Скриншот:** `light/onb0` на чистой установке.

**ON-2. Ранний запрос уведомлений и три «церемониальных» экрана — Improvement · High**
- **What:**
  - Шаг «Уведомления» просит разрешение для функций, которые по умолчанию выключены: их тумблеры спросят сами (`NotificationsSettingsPage.swift:37,42,50`). Текст «Умный будильник и подсказки — касанием по запястью» описывает вибрацию браслета, а для неё разрешение iOS не нужно.
  - «Наденьте браслет» — инструкция без действия.
  - «Всё готово / Добро пожаловать в NOOP» повторяет первый экран.
  - Кнопка «Войти в NOOP» подразумевает вход в аккаунт, которого нет.
- **Why:** `privacy.md › Best practices`: "asking for data before a person shows interest in the feature — can make it hard for people to trust your app." `onboarding.md › Additional requests`: "Postpone nonessential setup flows or customization steps."
- **Fix:** шаги `welcome, scan, profile, importData`; фраза «Наденьте браслет» переходит в шаг сканирования; последний шаг завершается кнопкой «Готово».
- **Скриншоты:** `light/onb1`, `light/onb5`, `light/onb6`.

**ON-3. Тексты запросов разрешений только на английском и обещают больше, чем правда — Improvement · High**
- **What:**
  - Все 7 `NS*UsageDescription` (`StrandiOS/Resources/Info.plist:62–75`, из `project.yml:295–305`) только на английском, `InfoPlist.xcstrings` нет. На русском iPhone системные алерты английские.
  - В строках по 2–3 предложения с довеском «Nothing leaves it.».
  - Health и Bluetooth обещают «Nothing leaves your device», что неверно при включённом Коуче (CR-10).
- **Why:** `privacy.md › Requesting permission`: "Aim for a brief, complete sentence that’s straightforward, specific, and easy to understand."
- **Fix:** `StrandiOS/Resources/InfoPlist.xcstrings` на все 10 языков, по одной фразе на ключ, например `NSBluetoothAlwaysUsageDescription` = «NOOP подключается к браслету WHOOP, чтобы считывать пульс, ВСР и заряд на этом iPhone.».

**ON-4. Экран условий выбивается из онбординга — Improvement · High**
- **What:**
  - `TermsGateView.swift` набран SF Rounded (`StrandFont.title1/.subhead`, 21–26), а соседние экраны — SF Pro со стеклянными капсулами.
  - Четыре юридических утверждения оформлены свитчами в `ScrollView` с многострочными подписями (56–66).
  - Сноска `textTertiary` даёт 3,58:1 (светлая) и 4,17:1 (тёмная).
  - Ссылку «TERMS.md, shipped with NOOP» нельзя открыть на iPhone.
  - Строки «Пожалуйста, …».
- **Why:** `toggles.md › Mobile (iOS, iPadOS)`: "Use the switch toggle style only in a list row." `onboarding.md › Additional content`: "If you must include these items within the onboarding flow, integrate them in a balanced way that doesn’t disrupt the experience."
- **Fix:** сверстать по метрикам `OnboardingWizard` (`SetupPage`): утверждения — ряды с ✓ в `Form`, TERMS.md — в листе из бандла, кнопка — «Принять». Показывать через `.fullScreenCover` с `.interactiveDismissDisabled()` (заодно закрывает CR-7). Сам гейт при сайдлоад-распространении оправдан: другого места показать соглашение нет.

**ON-5. Шаг «О вас» заранее заполнен предположениями — Improvement · Medium**
- **What:** дата рождения «26 сент. 2000 г.» (ровно 26 лет назад), пол «Мужской», 178 см, 75 кг подставлены как ответы. Пользователь может нажать «Продолжить», и зоны и калории посчитаются по чужим данным.
- **Why:** `entering-data.md` (вступление): "When you need information from people, design ways that make it easy for them to provide it without making mistakes." Принцип `design-principles.md › Responsibility`: "Only collect what your product needs to function, and handle it with care." Заполнение предположениями — суждение ревьюера.
- **Fix:** поля пустые со значением «Не указано», как у Apple в «Сведениях о здоровье»; «Продолжить» доступно всегда, но расчёты идут по данным только после ввода; пол — «Не указан / Женский / Мужской / Другой».
- **Скриншот:** `light/onb3`.

### 16. Мелкие элементы: NoticeCard, EmptyStateView, статусы синхронизации, подтверждения, меню, свайпы

(NoticeCard и HUD — CR-6; свайпы и меню Тренировок — W-1, W-7.)

**UI-1. Уведомления внутри приложения: английские термины и первое лицо — Improvement · Medium**
- **What:** «Признаки перегрузки — Выше нормы: resting HR, HRV.»; «Синхронизирую историю браслета» — приложение говорит от первого лица; «Как исправить» ведёт в справку, а не к действию.
- **Why:** `writing.md › Best practices`: "Use possessive pronouns sparingly." … "Avoid using we altogether because it may be unclear who the “we” in question refers to." Первое лицо от имени приложения — та же проблема (суждение).
- **Fix:** «Выше нормы: пульс покоя, ВСР.»; «Синхронизация истории браслета…»; действие — «Выполнить сопряжение».
- **Скриншот:** `light/notices`.

**UI-2. «Что нового» целиком на английском, пункты пронумерованы — Improvement · Medium**
- **What:** все 8 пунктов («A lift log you advance from the strap»…) английские в русском интерфейсе (`WhatsNewView.swift:15`). Маркеры `"\(index+1).circle.fill"` (`:91`) на пунктах, которые не последовательность. Кнопка «Продолжить» лежит поверх 8-го пункта.
- **Why:** `writing.md › Getting started`: "Choose simple, plain language and write with accessibility and localization in mind". Шаблон «01/02/03» на непоследовательном контенте — craft-линза скилла.
- **Fix:** строки в каталог; у каждого пункта свой SF Symbol, как в «Что нового» Apple; кнопка в `safeAreaInset(edge: .bottom)`.
- **Скриншот:** `light/sheet-whatsnew`.

**UI-3. Пустые состояния без следующего шага — Improvement · Medium**
- **What:** показатель без данных (M-3), «Все тренировки» с фильтром (W-13), «Пока нет закономерностей» (WM-4), пустой Коуч с одним заголовком.
- **Why:** `writing.md › Best practices`: "Provide clear next steps on any blank screens."
- **Fix:** везде `ContentUnavailableView { … } actions: { Button(…) }` с одной кнопкой. Для Коуча — ряд подсказок и первый чип «Бриф на сегодня».

**UI-4. `Haptics.swift` не используется и сам себе противоречит — Craft · Low**
- **What:** 0 вызовов; `.commit` = `.rigid` в UIKit-ветке (`:43`) и `.heavy` в SwiftUI-ветке (`:83`). Остальные хаптики в приложении — системные `sensoryFeedback`, их 8.
- **Why:** `playing-haptics.md › Best practices`: "Use haptics consistently throughout your app or game."
- **Fix:** файл удалить.

### 17. Виджеты, Live Activities, Dynamic Island, системные уведомления

(Текст виджетов мельче 11 pt — CR-9; подписи кнопок Live Activity — CR-5.)

**WG-1. Тап по виджету или баннеру не открывает нужный экран — Improvement · High**
- **What:** ни в одном из 4 виджетов и 4 Live Activity нет `.widgetURL` или `Link`. `StrandiOSApp.swift:329–333` понимает только `import-health`. `CoachBriefWidget.swift:11, 188` обещает «Tap to open Coach».
- **Why:** `widgets.md › Adding interactivity`: "Ensure that a widget interaction opens your app at the right location." `live-activities.md › Compact presentation`: "Ensure both leading and trailing elements link to the same screen."
- **Fix:** `.widgetURL(URL(string: "noop://coach"))` (и `workout`, `heart-rate`, `stress`, `today`, `intervals`) плюс маршрутизация в `.onOpenURL`.

**WG-2. Двойные поля: кольца не помещаются в маленький виджет — Improvement · High**
- **What:** свои `.padding(10/12/16)` (`NOOPWidget.swift:186, 199, 226`, `CoachBriefWidget.swift:151`) добавляются к системным ~16 pt: 158 − 2·26 = 106 pt, а три кольца по 40 pt требуют 120 pt. Ветки `else { .padding().background(.background) }` — мёртвый код.
- **Why:** `widgets.md › Choosing margins and padding`: "Use the standard margin width for widgets — 16 points for most widgets — to avoid crowding their edges and creating a cluttered appearance."
- **Fix:** четыре `.padding(...)` и мёртвые ветки удалить.

**WG-3. Пульс в основном виджете не проверяется на возраст — Improvement · High**
- **What:** снимок может быть часовой давности. NOOP-виджет пишет «58 bpm», а соседний «Пульс» — «—» (`NOOPWidget.swift:85, 108–109, 217, 297` против `HeartRateWidget.swift:110–112`). В описании обещан «live HR».
- **Why:** `widgets.md › Mobile (iOS, iPadOS)`: "Widgets don't show real-time information."
- **Fix:** `HrDisplay.resolve(bpm:newestPointTs:now:)` во всех четырёх местах; из описания убрать «live».

**WG-4. Статус подключения — только красная/зелёная точка 8 pt под шапкой «NOOP» — Improvement · High**
- **What:** `NOOPWidget.swift:231–242`. В режимах tinted/clear обе точки становятся белыми, а шапка съедает строку маленького виджета.
- **Why:** `accessibility.md › Vision`: "people who are color blind may have particular difficulty with pairings such as red-green and blue-orange." `widgets.md › Best practices`: "When you include brand elements, people seldom need your logo or app icon to help them recognize your widget."
- **Fix:** `headerRow` удалить; устаревшие данные показывать «—» и временем обновления.

**WG-5. Режимы рендеринга iOS 26, превью и Dynamic Type — Improvement · Medium**
- **What:**
  - Дуга кольца без `.widgetAccentable()` (`NOOPWidget.swift:390`).
  - `healthBody` на vibrant (`CoachBriefWidget.swift:95, 98`).
  - Плейсхолдеры HR, Stress и Coach строятся с `snap: nil`, и в галерее видны «—» без графика (`HeartRateWidget.swift:22, 26`, `StressWidget.swift:24, 28`, `CoachBriefWidget.swift:37–40`).
  - Заголовки и подписи набраны фиксированным кеглем (`HeartRateWidget:123–141`, `StressWidget:152–178`); фиксированное число в кольце оправдано.
- **Why:** `widgets.md › Accented`: "Group widget components into an accented and a primary group." `widgets.md › Previews and placeholders`: "Design a realistic preview to display in the widget gallery." `widgets.md › Displaying text in widgets`: "widgets support Dynamic Type sizes from Large to AX5".
- **Fix:** `.widgetAccentable()`; `.secondary`/`.primary` вместо цветов на vibrant; `context.isPreview ? .placeholder : WidgetSnapshot.load()`; `.footnote.weight(.semibold)` / `.caption` / `.caption2` и `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` на корне medium-виджетов.

**LA-1. Live Activity пульса не заканчивается: продлевается каждый час — Improvement · High**
- **What:** `LiveHRBannerLifecycle.swift:31` (`renewAfter = 60*60`), `LiveActivityController.swift:157–164`; неизменившееся число пере-пушится ради свежести. На экране блокировки главное значение — «—».
- **Why:** `live-activities.md › Best practices`: "Offer Live Activities for tasks and events that have a defined beginning and end." `live-activities.md › Starting, updating, and ending a Live Activity`: "Update a Live Activity only when new content is available."
- **Fix:** HR-активность привязать к событию с концом (тренировка); `.renew` убрать; в конце — `end(final, dismissalPolicy: .after(.now + 15*60))`. Круглосуточный пульс — задача виджета.
- **Скриншоты:** `shell/lock-hr`, `shell/island-expanded`.

**LA-2. Компактный и минимальный вид Dynamic Island — Improvement · Medium**
- **What:**
  - В минимальном виде HR, Lift и Sync показывают статичную иконку (`NOOPLiveActivity.swift:62–63`, `LiftLiveActivity.swift:65–66`, `SyncLiveActivity.swift:70–72`).
  - Время «0:45» прижато вправо внутри ширины «00:00», и у камеры остаётся около 9 pt пустоты (`LiveActivityChrome.swift:74, 83`).
  - У Lift левая половина меняет цвет посреди сессии.
  - Кнопка Lift на экране блокировки слева, а в развёрнутом виде справа (`LiftLiveActivity.swift:101` против `:29`).
- **Why:** `live-activities.md › Minimal presentation`: "If possible, display updated information rather than just a logo, while ensuring people can quickly recognize your app." `live-activities.md › Compact presentation`: "Keep content as narrow as possible and ensure it's snug against the TrueDepth camera." `live-activities.md › Expanded presentation`: "Maintain the relative placement of elements to create a coherent layout between presentations."
- **Fix:** в минимальном виде — число пульса / кольцо отдыха через `ProgressView(timerInterval:)`; у `ActivityClock` параметр `alignment: .leading` для compact trailing; кнопку ставить одинаково.
- **Скриншот:** `shell/island-compact`.

**LA-3. Мелочи баннеров — Craft · Low**
- **What:**
  - Отступ у интервалов 16 pt, у остальных 14 (`IntervalLiveActivity.swift:23`).
  - Цифры `.light` (46/36 pt), вторичные строки `.regular`.
  - `.font(15)` в Sync перебивается 17 pt в `ActivityClock` (`SyncLiveActivity.swift:54` → `LiveActivityChrome.swift:85`).
  - «46%» в баннере против «46 %» в приложении.
  - Баннеры исчезают с `.immediate`, без итога.
- **Why:** `live-activities.md › Lock Screen presentation`: "The standard layout margin for Live Activities on the Lock Screen is 14 points." `live-activities.md › Best practices`: "Use large, heavier-weight text — a medium weight or higher."
- **Fix:** 14 pt; `.medium` для вторичных строк; шрифт `ActivityClock` параметром; проценты через `.formatted(.percent)`; `dismissalPolicy: .after(.now + 15*60)`.

**NT-1. Уведомление о болезни: данные о здоровье на экране блокировки и «Up: HRV −18%» — Improvement · High**
- **What:** тело вида «Up: RHR +6, HRV −18% and Respiration up» видно посторонним (`HealthAlertBanner.swift:24–36`, `IllnessNotifier.swift:32–37`): нет категории с плейсхолдером. «Up:» стоит перед падением ВСР. Заголовок «Your signals agree you're unwell» звучит как диагноз.
- **Why:** `notifications.md › Best practices`: "Avoid including sensitive, personal, or confidential information in a notification." `notifications.md › Content`: "Provide generically descriptive text to display when notification previews aren't available."
- **Fix:** `UNNotificationCategory(identifier: "health", actions: [], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: String(localized: "Health notice"))` плюс `content.categoryIdentifier = "health"`; тело — список без «Up:»; заголовок — «Показатели вне нормы».

**NT-2. Одно событие — несколько уведомлений; регистр и имена — Improvement · Medium**
- **What:**
  - На один цикл разряда батарея присылает 4 разных id (`BatteryNotifier.swift:84, 116, 140, 171`), `threadIdentifier` нет.
  - Заголовки уведомлений в sentence case.
  - У брифа три имени: «Coach Brief», «Today's brief», «Morning Brief».
  - «Optimal strain reached» при метрике «Усилие».
  - На переднем плане уведомление дублирует баннер внутри приложения (`NotificationPresenter.swift:31`), а по тапу открывается только Коуч (`:41–44`).
- **Why:** `notifications.md › Best practices`: "Avoid sending multiple notifications for the same thing, even if someone hasn't responded." `notifications.md › Content`: "Use title-style capitalization and no ending punctuation." `notifications.md › Best practices`: "Handle notifications gracefully when your app is in the foreground."
- **Fix:** один id `"battery"` с заменой плюс `threadIdentifier`; «Smart Alarm», «Low Battery», «Effort Target Reached»; одно имя — «Утренний бриф»; на переднем плане для `illness-watch` — `[.list]`; маршрут тапа — по `request.identifier`.

### 18. Тексты и терминология (сквозное)

**X-1. Английские строки в русском интерфейсе; каталог переведён на 1 язык из 10 — Improvement · High**
- **What:**
  - По-английски показаны: вопросы журнала (WM-1), «Что нового» (UI-2), «resting HR, HRV» в уведомлениях, «61 bpm», единицы анализов, «Custom (OpenAI-compatible)», тестовые домены, системные запросы разрешений (ON-3), VoiceOver-строки «Что читает NOOP» (CR-5), ошибки Коуча (CO-4).
  - «Categories», «Mindfulness», «All Metrics», «Copied», «Open Devices», «How to Fix» переведены только на русский.
- **Why:** `writing.md › Getting started`: "Choose simple, plain language and write with accessibility and localization in mind".
- **Fix:** все пользовательские строки — через `String(localized:)`; данные-ключи отображать через каталог; в CI — `Tools/i18n_audit.py`.

**X-2. Один термин на одно понятие — Improvement · Medium**
- **What:**
  - Устройство: «Браслет» (корень, Пульс) и «Ремешок» («Будильник ремешка», «Журнал ремешка»).
  - «Заряд»: показатель и батарея.
  - «ВСР», «HRV» и «Вариабельность» для одного показателя.
  - «Отбой», «Время отхода ко сну», «Отход ко сну».
  - Одно число — «Отдых» на Сводке и «Оценка сна» на Сне.
  - «Показатели» — это и Vitals, и Metrics.
  - «Дыхание» (быстрое действие) и «Осознанность» (экран).
  - «Пульс в реальном времени» и «Пульс».
  - «Запись в журнал» и «Журнал».
  - «Начать тренировку» открывает список, а не запускает тренировку.
- **Why:** `writing.md › Getting started`: "Create a list of common terms, and reference that list to keep your language consistent."
- **Fix:** глоссарий в `docs/` — «Браслет», «Батарея браслета», «ВСР», «Отход ко сну», «Основные показатели» (Vitals), «Осознанность», «Пульс», «Журнал», «Тренировки»; быстрым действиям — имена рядов «Обзора».

**X-3. Числа, даты, единицы — Improvement · Medium**
- **What:**
  - Точка вместо запятой в Lab Book, Дневнике и импорте (CR-11, LB-1).
  - «46%» против «46 %».
  - «bpm» против «уд/мин».
  - Длинное тире в диапазонах дат против короткого у Apple.
  - Форматы `en_US_POSIX` (LV-2).
- **Why:** `text-fields.md › Best practices`: "Don’t assume the actual presentation of data, however, as formatting can vary significantly based on people’s locale."
- **Fix:** только `FormatStyle` с `AppLanguage.activeLocale`: `.number`, `.percent`, `Measurement.FormatStyle`, `Date.IntervalFormatStyle`.

---

## Craft notes

**Точка зрения.** Дизайн сознательно отказывается от своей: цель — «1 в 1 как Apple». Это оправдано. Продукт — компаньон к чужому железу, и его ценность в том, чтобы данные ремешка выглядели как данные «Здоровья». Узнаваемое своё осталось в двух местах:
- **триада Заряд · Усилие · Отдых** на карточке «Активность» — единственная идея, которой нет у Apple;
- **чёрный экран записи** с цифрами 88–120 pt и зелёными часами, как на Apple Watch.

Этого достаточно. Больше акцентов не нужно, всё остальное должно быть тихим.

**Craft-1. Триада не имеет своего цвета — Improvement · High (см. S-1).** Единственная собственная идея дизайна одета в цвета колец Apple (Move/Exercise/Stand), а на своих страницах — в другие цвета. Чтобы триада стала подписью продукта, ей нужна одна тройка цветов везде: кольца, заголовки, графики, виджеты, Live Activity.

**Craft-2. Два шрифта «Здоровья» — Improvement · Medium.** Сводка и карточки сна набраны SF Rounded (`StrandFont.headline/body/number`, заголовок секции `rounded(22)`). Страница показателя, расписание, тренды и настройки — SF Pro (`StrandFont.pro`). `Typography.swift:111–112` сам признаёт, что «Здоровье» использует SF Pro. У Apple в «Здоровье» SF Rounded только в цифрах колец, а в «Фитнесе» — в цифрах метрик.
- **Why:** `typography.md › Conveying hierarchy`: "Minimize the number of typefaces you use, even in a highly customized interface."
- **Fix:** текст везде SF Pro; Rounded оставить только цифрам колец и экрана записи.

**Craft-3. Одна анатомия, четыре реализации — Craft · Low.**
- Заголовок секции сделан 4 способами: `SummarySectionHeader` (rounded 22), `SleepScheduleHeader` (pro 22 bold), `MetricDetailView.sectionHeader`, инлайн в `MetricStressDay`.
- Карточка «Подборки» — 3 копии с разными параметрами: столбцы 64/44/96, цифры 22/22/30.
- Графики на Canvas стоят рядом со Swift Charts.
- Фон карточки рисуется вручную в `SleepMoreRow`, `optionsCard` и строках «Все показатели» вместо `SummaryCard`.
- **Why:** `design-principles.md › Familiarity`: "Once you establish a behavior or appearance for an element, apply it throughout your design."
- **Fix:** один `SectionHeader`, один `HighlightCard`, один `SummaryCard`. Графики — только Swift Charts: они дают и доступность (CR-3).

**Craft-4. Убрать один аксессуар — Craft · Low.** Кандидаты, в порядке пользы:
- ручной `tabBarClearance = 76` (`Components.swift:14`, 13 мест): даёт пустой хвост 108 pt в шторках без таб-бара;
- шапка «NOOP» в виджете;
- строка `next` в Live Activity зала;
- второй «+» в Журнале;
- «+» в Коуче.

## Где мы не 1 в 1 с Apple

| Экран | Приложение Apple (iOS 26) | Как у Apple | Как у нас | Рекомендация |
|---|---|---|---|---|
| Сводка | Здоровье → Сводка | Нет пейджера дней; «Закрепленное / Изменить»; карточка «Активность» — 2 колонки + 1 под ними, «09:41 ›» | ‹ Сегодня ›, «Закреплено», 3 колонки без шеврона | Пейджер — решение владельца, оставить. Шеврон и «Закреплённое» — как у Apple |
| Сводка, кольца | Фитнес / Здоровье | Кольца = Move/Exercise/Stand | Кольца = Заряд/Усилие/Отдых в цветах Apple | Осознанное отличие; нужен один цвет на показатель (S-1) |
| Сон | Здоровье → Сон | Д·Н·М·6М на странице, разбивка оценки под кольцом | Диапазоны — в шторке «Больше данных о сне», разбивки нет | Решение владельца; озвучить разбивку (SL-1) |
| Страница показателя | Здоровье → тип данных | Д·Н·М·6М·Г; «Об этом показателе» — секция внизу | Н·М·6М·Г; описание в поповере ⓘ | Добавить «Д» там, где есть внутридневные данные |
| Все показатели | Здоровье → поиск | Поиск находит типы данных | Поиск «Обзора» — только 9 разделов | K-1 |
| Расписание сна | Здоровье → Полное расписание | «Расписание сна» + «Фокусирование «Сон»», «Будние дни / Править» | «Будильник ремешка», «Будни / Изменить» | Близко; добавить связь с Фокусом «Сон» (AL-1) |
| Редактор расписания | Здоровье → Настройка расписания | Жирные заголовки секций, «Добавить» | Серый заголовок, ✓ | AL-3 |
| Будильник | Часы | AlarmKit, полноэкранный «Стоп/Отложить» | Уведомление `.active` | AL-1 |
| Тренировки | Фитнес → Тренировка | Тёмная тема всегда, под карточкой ряд «Медиа / Голос / Цель», отсчёт 3-2-1 | Светлая тема с бледно-зелёными карточками, старт сразу | Отсчёт 3-2-1 с пропуском по тапу; светлая тема — решение владельца, проверить контраст (CR-2) |
| Экран записи | Apple Watch → Тренировка | «Завершить» красная, «Пауза» жёлтая, подписи, слово «Пауза» | Серые круги без подписей | W-5 |
| Интервалы | Фитнес → Пользовательская тренировка / Часы → Таймер | Этапы списком («Разминка 10:00»); таймер — колесо ч/мин/с, кольцо | −/+ по 5 с, линейная полоса | Колесо `DatePicker(.countDownTimer)` вместо −/+ |
| Оценка усилия | Фитнес | Шкала «Лёгкая … На пределе» | Поле «RPE (1–10)» | W-4 |
| Карта | Фитнес | Статичное превью → полноэкранная карта | Интерактивная карта в прокрутке | W-14 |
| Мини-плеер | Музыка | Монохромный текст, компактный вид при прокрутке, свайп вниз закрывает плеер | Цветной таймер, нет компактного вида, закрывается только ⌄ | K-4 |
| Пульс | Apple Watch → Пульс | Технических фраз нет, сердце бьётся в ритм | «Connected, waiting for a streaming state», 60 уд/мин всегда | LV-1, LV-4 |
| Осознанность | Apple Watch → Осознанность | Итог: время и пульс; стеклянные кнопки | + ВСР «+14 %», серые круги, своя капсула «Готово» | BR-1, BR-4 |
| Коуч | Сообщения | Строка «iMessage · Encrypted», «+» = приложения, волна диктовки | «Только по запросу» (неправда), «+» = подсказки, без волны | CR-10, CO-1, CO-7 |
| Журнал | Здоровье → Лекарства | Бирюзовые строки «Внесение», полоса недели | То же | Почти 1 в 1 — оставить |
| Что вами движет | Здоровье → Подборки | Без сегментов, коэффициентов r и ⓘ | Сегменты, r, ⓘ | WM-2 |
| Lab Book | Здоровье → Результаты анализов | Полоса диапазона с положением значения, русские единицы | Числа «Диапазон 50–125», английские единицы, дисклеймер | LB-1; полоса диапазона — `Gauge(.linearCapacity)` |
| Настройки | Здоровье / Фитнес → аватар | Лист аватара = настройки | Лист → «Настройки» с повтором | ST-2 |
| Оформление | Настройки → Экран и яркость | Системная настройка | Копия внутри приложения | ST-1 |
| Устройства | Watch → Все часы; Настройки → Bluetooth | Тап по ряду = переключить или подключить, ⓘ = детали; «Забыть» — action sheet | Тап = детали, ⓘ — картинка; алерты | DV-1, DV-4 |
| Сопряжение | Карточка AirPods | Фиксированная высота, без «назад» | Детенты 600/large, «‹», непрозрачная заливка | DV-5 |
| Условия | Установка iOS | Страница с «Принять» | Свитчи в ScrollView, SF Rounded | ON-4 |
| Виджеты | Фитнес / Здоровье | Один набор концентрических колец, без бренда | Три кольца в ряд + шапка «NOOP» + подвал | WG-2, WG-4 |
| Live Activity | Часы → Таймер | В минимальном виде оставшееся время, в конце итог | Иконка, исчезает сразу | LA-2, LA-3 |
| Пункт управления | Часы, Фитнес | Кнопки в Пункте управления | Нет ни одного `ControlWidget` | Добавить «Интервалы» и «Синхронизировать браслет» (`controls.md › Best practices`: "launching a Live Activity from a control creates an easy and seamless experience") |

## Где выглядит «шаблонно»

Проверка craft-линзой скилла. Ни одного из трёх типовых сгенерированных стилей (кремовый с засечками и терракотой; почти чёрный с одним кислотным акцентом; газетные линейки) в приложении нет: визуальный язык взят у Apple и повторён честно. Шаблонность здесь другого рода: «по-Apple-ски, но собрано из копий».

1. **«Что нового»: нумерованные кружки 1–8** на непоследовательном контенте. Это прямой шаблон «01 / 02 / 03» из craft-линзы (UI-2).
2. **Большая цифра над мелкой подписью в каждой карточке.** У Apple это оправдано одним значением на карточку, у нас так же. Но на Сводке при AX (CR-1) цифра становится мельче подписи, и шаблон ломается в худшую сторону.
3. **Четыре заголовка секций, три карточки «Подборки», два набора нейтральных фонов** (Craft-3, K-7). Каждый экран копировал Apple отдельно, и системы из этого не сложилось.
4. **Декоративные капсулы** Min/Max/Peak в виджетах и мини-график из двух точек, похожий на переключатель (S-4).
5. **Текстовые «пояснения» в подвалах**, которые владелец уже вычищал в Настройках, остались в Тренировках, Сне, Lab Book и на экране условий.

## What works

- **Каркас iOS 26 честный.** `TabView` с тремя вкладками и `Tab(role: .search)`. Повторное касание вкладки возвращает в корень. Нативный `tabViewBottomAccessory` на iOS 26.1. Один ✕ через `Button(role: .close)` (29 мест), монохромные глифы тулбаров через `.barGlyph()` (16 мест), одна акцентная ✓.
- **Стекло почти только на функциональном слое** и только системное (`glassEffect(.regular)`, фолбэк на `.regularMaterial`). Поэтому «Уменьшить прозрачность» и «Увеличить контраст» для таб-бара, аксессуара и пузырей Коуча система обрабатывает сама: `rt/*` чистые, за исключением K-6.
- **Тёмная тема.** Все 64 экрана в `dark/*` читаются, тёмные варианты цветов проходят контраст (≥ 4,83:1).
- **Reduce Motion закрыт одним гейтом** `NoopMotionState.poseStill`: сердце Пульса, точки «печатает…», полёт пузыря, цветок Дыхания, кольца и гейджи.
- **Карточки трендов** — образцовая подпись для VoiceOver: показатель, вывод и оба средних с числами (`HealthTrendCard.swift:44–49`). `DayPager` подписан «Предыдущий/Следующий день» и правильно отключается.
- **Разрешения в контексте:** геолокация — при GPS-тренировке, уведомления — при включении тумблеров, HealthKit — по кнопке. В онбординге перед системным запросом одна кнопка «Продолжить», как требует `privacy.md`.
- **`ManualWorkoutSheet`** — образцовая форма: правильные клавиатуры, конкретные ошибки прямо при вводе, ✓ отключена, пока данные невалидны. Портит её только разбор запятой (CR-11).
- **Живые данные обновляются листьями:** каждый тик 1 Гц перерисовывает только цифру.
- **Журнал ≈ «Лекарства» Apple:** почти 1 в 1, включая бирюзовые строки и полосу недели.
- **Удаление сна** — через «Отменить» в интерфейсе, а не через алерт; нужно только убрать таймер (CR-6).
- **Live Activities** — одна система (`ActivityDisc`, `ActivityControl`, `ActivityClock`): самотикающие часы через `Text(timerInterval:)`, честное «–» по `staleDate`, отступ 14 pt, одновременно один баннер.
- **Коуч в движении** — анимации сняты с «Сообщений» покадрово. Это самый сильный крафт в приложении.

## Platform notes

- **iPhone.** Всё выше проверено на iPhone Air (420×912 pt). Самые узкие места: карточка «Активность» (S-2) и ряды настроек с длинным значением — на iPhone SE/mini они переполнятся раньше.
- **iPad и iPhone Duo.** В `project.yml` iPad есть. `TabView` на регулярной ширине сам станет боковой панелью, но экраны на `ScrollView` с фиксированной шириной карточек не проверялись. `designing-for-iphone-duo.md` не применялся: раскладка на две панели не заявлена.
- **macOS.** Код общий (`Strand/`). Потолок `...accessibility1` на macOS ничего не делает. Правка `StrandFont.pro` (CR-1) затронет и Mac, но размеры там не изменятся: у macOS нет Dynamic Type, а стили на Large совпадают с текущими pt. Mac-сборку проверить после правки.
- **SwiftUI iOS 26.** Скриншоты сняты в 26.5. Для `tabViewBottomAccessory` нужна 26.1+, фолбэк — капсула. Фиксы с `accessibilityChartDescriptor`, `accessibilityRepresentation`, `AnyLayout`, `ViewThatFits` и `AccessibilityNotification` доступны на iOS 17+ — это текущий deployment target.
- **Виджеты и Live Activities.** Фиксированные pt в Live Activity допустимы: HIG задаёт размеры в pt. Для текста виджетов действует минимум 11 pt и Dynamic Type до AX5.

---

## План исправлений (от Critical к полировке)

Каждый шаг — отдельный коммит: собрать, заснять светлую и тёмную тему и AX5, закоммитить.

**Этап 1. Доступность (Critical).**
1. **CR-1, шаг 1:** `Typography.swift` — сопоставить размеры с текстовыми стилями (`pro`, `rounded`, `number`). Это одна правка, примерно 430 мест начнут масштабироваться, на Large вид не изменится.
2. **CR-1, шаг 2:** `@ScaledMetric` для крупных чисел. `AnyLayout`/`ViewThatFits` для карточки «Активность», плиток сна, подходов, зон, рядов настроек. `minHeight` вместо фиксированных высот. Снять потолок `...accessibility1`. Проверка — `ax/*`.
3. **CR-2:** в `Color` добавить варианты высокого контраста; текстовые токены категорий и Фитнеса с контрастом ≥ 4,5:1; системные цвета и фоны — системными API (`Color.blue`, `.systemGroupedBackground`); глифы на заливке — по яркости. Проверка — `ic/*` должны отличаться от `light/*`.
4. **CR-3:** графики — подписи меток, `accessibilityChartDescriptor`, сегменты словами, `OverviewHRChart` с верной метрикой и зумом.
5. **CR-4:** циферблат расписания — `accessibilityRepresentation` с двумя `DatePicker` и кнопками времени.
6. **CR-5:** подписи для часов записи, степперов интервалов, ✓ («Готово»), кнопок Live Activity, состояний подходов, «Что читает NOOP».
7. **CR-6:** `NoticeCard` 44×44 и без обрезки; убрать 7-секундный таймер отмены; HUD — `AccessibilityNotification` и затухание при Reduce Motion.
8. **CR-7:** шлюзы первого запуска — `fullScreenCover` или `accessibilityHidden` для `RootTabView`.
9. **CR-8:** «Спокойствие» — визуальный ритм цветка и проверка настройки вибрации.
10. **CR-9:** текст виджетов ≥ 11 pt, `.secondary`.

**Этап 2. Сломанное поведение и данные (Critical).**
11. **CR-10:** Коуч — убрать автоматический бриф; футер «что уходит» всегда; поправить строки разрешений.
12. **CR-11:** разбор чисел с учётом локали; колёса веса не перезаписывают нетронутое; `.numberPad` для целых полей.
13. **CR-12:** голосовой ввод — состояние «стоп», без дублей; запрос разрешения по касанию.

**Этап 3. Конвенции iOS 26 (High).**
14. Разрушительные действия: W-1 (свайп тренировки + undo), W-2 (шторки не теряют ввод), W-3 (✕ интервалов), ST-3 (импорт из файла), CO-3 («Отключить»), LB-2.
15. Навигация: K-2 (переходы вместо шторок), K-3 (Коуч без скрытия таб-бара), K-1 (поиск по показателям), ST-2 (лист профиля = настройки).
16. Первый запуск: ON-1 (Bluetooth в контексте), ON-2 (4 шага вместо 7), ON-3 (`InfoPlist.xcstrings`), ON-4 (экран условий).
17. Цвет со смыслом: S-1 и Craft-1 (одна тройка цветов триады; работа и отдых одинаковы везде); SL-1, SL-2.
18. Устройства: DV-1 (ⓘ и тап по ряду), DV-2 (причина ошибки BLE), DV-3 (импорт в мастере).
19. Коуч: CO-1 (раскрытие ИИ, без выдуманного «Доставлено»), CO-2 (стоп и повтор).
20. «Что вами движет» и Lab Book: WM-1 (перевод вопросов), WM-2 (без причинности и r/d, порог выборки).
21. Уведомления и баннеры: AL-1 (AlarmKit / time-sensitive), NT-1 (скрытое превью), WG-1 (deep links), WG-2, WG-3, WG-4, LA-1.
22. Оформление: ST-1 (убрать настройку темы или переименовать «Автоматически»), X-1 (английские строки).
23. BR-1 (итог дыхания без ложной точности), S-2 (карточка «Активность»).

**Этап 4. Паттерны (Medium).**
24. K-4 … K-8, S-3, SL-3, SL-4, M-1 … M-6, W-4 … W-12, AL-2, LV-1 … LV-3, BR-2, BR-3, CO-4 … CO-6, JR-1, JR-2, WM-3, LB-1, ST-4 … ST-8, DV-4, DV-5, ON-5, UI-1 … UI-3, WG-5, LA-2, NT-2, X-2 (глоссарий), X-3 (форматы), Craft-2 (один шрифт текста).

**Этап 5. Полировка (Craft · Low).**
25. K-9, K-10, S-4, SL-5, SL-6, M-7, W-13, W-14, AL-3, LV-4, BR-4, CO-7, JR-3, WM-4, LB-3, ST-9, ST-10, UI-4, LA-3, Craft-3, Craft-4.

После этапов 1–2 оценка по шкале скилла станет **Good**; после этапа 3 — **Excellent**, при условии что триада Заряд · Усилие · Отдых получит свою тройку цветов.
