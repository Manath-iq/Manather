# Manather — контекст проекта для AI-ассистентов

> **Этот файл — главный источник правды о продукте.** Каждая новая AI-сессия должна
> прочитать его перед любой работой. Обновляй его, когда добавляешь крупные фичи.

---

## 1. Что это за продукт

**Manather — нативное macOS-приложение для вайб-кодеров.**

Это персональная библиотека всего, из чего вайб-кодер собирает свои проекты:

- 🖼 **Референсы** — картинки, скриншоты дизайнов, видео (например, для фона сайта), гифки
- 🧩 **Skills** — markdown-инструкции для AI-агентов (Claude Code skills и подобные)
- 🔌 **MCP-серверы** — конфиги серверов Model Context Protocol (команда запуска, JSON-конфиг)
- 💻 **Сниппеты кода** — готовые кусочки кода, паттерны, шаблоны
- 🔗 **Веб-ссылки** — закладки с автоматическими скриншотами страниц
- ✍️ **Промпты** — AI-промпты хранятся прямо в карточке любого ассета

**Ключевая идея:** пользователь собирает ассеты в **Проекты** (Projects), а потом
**одной кнопкой экспортирует проект как «context pack»** — папку с файлами,
`CONTEXT.md` и `manifest.json`, которую можно положить в репозиторий, чтобы
AI-агент (Claude Code и т.п.) построил проект на основе этих материалов.

### Кто пользователь

Вайб-кодеры: люди, которые делают проекты с помощью AI-агентов, часто без глубокого
опыта программирования. Им нужно одно место для хранения «строительных блоков»
и быстрый способ скормить их нейросети.

### Чем НЕ является

- Это не клон GatherOS — от него взят только визуальный стиль (исходное дизайн-ТЗ
  хранится локально у владельца и не входит в публичный репозиторий).
- Это не дизайнерская библиотека типа Eagle — дизайн-референсы лишь один из типов контента.

---

## 2. Текущее состояние (что уже работает)

### Библиотека (вкладка Library)
- Masonry-сетка (Pinterest-style), колонки 2–6 через слайдер
- Категории: All / Unsorted / Trash (мягкое удаление с восстановлением)
- Поиск (иконка → разворачивается, ⌘F): по названию, промпту, заметкам, тегам, коду
- Сортировка: Most recent / Oldest / Name A–Z / Name Z–A
- **Фильтр по 7 цветам** — кружки в тулбаре; доминантные цвета извлекаются при
  импорте и фоново для старых ассетов (`ColorIndex.swift`)
- Карточки коллекций со стопкой превью над сеткой («N saves»)
- Drag & Drop из Finder, импорт через диалог, FAB-меню (+)
- **Кастомное контекстное меню** (правый клик) — тёмная плашка с затемнённым
  фоном вместо нативного меню (`CustomContextMenu.swift`): Open, Copy Prompt,
  Copy Image, Add to Collection/Project (под-страницы), Duplicate, Reveal in
  Finder, Export, Move to Trash; в корзине — Restore / Delete Permanently
- **Зум интерфейса** ⌘+/⌘−/⌘0 (как в Notes), сохраняется (`uiZoom` в AppStorage)
- **Анимации**: общие кривые движения в теме (`overlayMotion`, `uiMotion`),
  скользящие капсула таба и подчёркивание категории, единый ховер карточек
  (`hoverLift`), плавный zoom открытия/закрытия просмотра

### Типы ассетов (`AssetItem.assetType`)
- `image`, `gif`, `video` — файлы копируются в сэндбокс, превью кешируются
- `webLink` — скриншот страницы генерируется автоматически (`WebsiteScreenshotManager`)
- `codeSnippet` — код с подсветкой языка
- `mcpServer` — конфиг MCP-сервера (JSON в `codeContent`, команда в `codeLanguage`)
- `skill` — markdown-инструкция для AI-агента

### Detail View (просмотр ассета)
- Открывается кликом по карточке, навигация ←/→, зум/пан, Esc — закрыть
- Тёмный glassmorphic-инспектор: превью, цветовая палитра (клик — копия hex),
  кнопка «Generate variation» (заглушка до подключения AI), Name, URL,
  «+ Add a note», Image Prompt с Copy, Collections как chips, Tags с Auto-tag

### Данные
- SwiftData, модель `AssetItem` (один файл = один ассет, плоская модель)
- Группировка: `collectionName: String?` (одно значение на ассет, НЕ many-to-many).
  Поле `spaceName` (бывшие «Проекты») оставлено в модели, но в UI не используется:
  Проекты объединены с Коллекциями (вкладки теперь Library / Collections / Boards).
- **Коллекции — реальные объекты** (`AssetCollection`, см. `AssetCollection.swift`):
  отдельная SwiftData-сущность `{ id, name, dateAdded }`. Ассет по-прежнему
  ссылается на коллекцию по имени (`collectionName`), поэтому вся группировка/
  фильтр/экспорт работают как раньше. Сущность нужна, чтобы коллекция могла быть
  **пустой** (создал → потом наполняешь) и не исчезала. На вкладке Collections —
  карточка «New collection» (`NewCollectionSheet`), правый клик по коллекции —
  Export / Delete (Delete только убирает метку с ассетов, сами ассеты остаются).
  Клик по коллекции открывает её **внутри вкладки Collections** отдельным экраном
  (`collectionDetailView`: «← Collections», название, masonry-сетка её ассетов,
  меню Export/Delete) — НЕ переходом в Library с фильтром. Состояние —
  `openCollection: String?`; «Unassigned» открывается так же (read-only).
  Правый клик по ассету → «Add to Collection» → «New Collection…» создаёт коллекцию
  на месте. Старые имена коллекций с ассетов один раз поднимаются в объекты
  (`seedCollectionsFromAssets`, идемпотентно).
- Файлы: `~/Library/Application Support/ManatherAssets/`
- Кеш изображений: `ImageCache` (NSCache, квантованные размеры тамбнейлов)

### Экспорт коллекции (build pack)
- Правый клик по коллекции (или меню «…» внутри коллекции) → **Export for…** →
  выбор формата: **Claude Code / AGENTS.md / Generic** (`ExportTarget`).
- После выбора формата всплывает окно **`ExportGoalSheet`** — свободное поле
  «What are you building?», куда пользователь пишет цель проекта (сайт/приложение/
  бот, стек, аудитория). Текст опционален и идёт секцией **🎯 Goal** в entry-файл,
  `context.md` и в `manifest.json` (`goal`); пусто → нейросеть выводит цель из
  материалов. Передаётся через `pendingExport`/`PendingExport` в `export(…, goal:)`.
- Создаёт **двухуровневую** папку-бриф, из которой нейросеть строит проект:
  - **entry-файл** (`CLAUDE.md` / `AGENTS.md` / `README.md`) — короткий «пульт»:
    что это, карта папок и секция **▶ Start** (по слову «start» нейросеть читает
    `context.md` и строит проект; формулировка универсальная, не только сайт).
  - **`context.md`** — каталог: каждый ассет с метаданными (описание, промпт
    генерации, палитра, размеры, теги, источник, путь к файлу).
  - Контент по папкам: `images/` (медиа), `snippets/` (код); скиллы и MCP кладутся
    по месту формата.
  - **Авто-настройка для Claude Code**: скиллы → `.claude/skills/<slug>/SKILL.md`,
    MCP → `.mcp.json` в корне (сессия Claude Code в папке работает сразу). Для
    AGENTS/Generic — `skills/<slug>.md` и `mcp/mcp.json`.
  - `manifest.json` — машиночитаемый индекс.
- Вся логика в `ContextPackExporter.swift` (один `writePack` + дескриптор `Layout`
  на формат).

### Настройки — окно (Settings)
- Шестерёнка в правом верхнем углу открывает **модальное окно по центру**
  (`showSettings` + `settingsOverlay` в `GalleryGridView.swift`; контент —
  `SettingsView.swift`). Затемнённый фон, закрытие по клику вне / ✕ / Esc
  (Esc — локальный `NSEvent`-монитор на keyCode 53, как в `BoardView`).
- Вкладки (левый сайдбар): **General** (сводка библиотеки, Export Library .zip,
  Load Demo, Clear Cache, тёмная тема, хоткей скриншота), **AI Providers**,
  **CLI Agents**, **About**.
- **AI Providers** — подключение нейросетей по API-ключу. Провайдеры в
  `AIProvider.swift`: OpenRouter, OpenAI, Anthropic, Google Gemini, xAI (Grok),
  DeepSeek, Mistral, Ollama (local). Ключ → **Keychain** (`KeychainStore.swift`),
  НИКОГДА не в UserDefaults/логах; ввод через `SecureField` с показом/скрытием.
  Кнопка **Test connection** (`AIProviderStore.swift` → `ProviderConnectionService`,
  async URLSession): OpenAI-совм. `GET /models` (Bearer), Anthropic `GET /v1/models`
  (`x-api-key`+`anthropic-version`), Gemini `GET /v1beta/models?key=`, Ollama
  `GET /api/tags`. Несекретное (модель, baseURL для Ollama, провайдер по
  умолчанию) — в UserDefaults. Сами AI-фичи (Generate variation, auto-tag,
  генерация context.md) — ещё не подключены к этим ключам (следующий шаг).
- **CLI Agents** — Claude Code (`claude`), Codex CLI (`codex`), Antigravity CLI
  (`antigravity`, замена Gemini CLI), Gemini CLI (`gemini`, legacy).
  `CLIAgent.swift` + `CLIAgentDetector` детектит установку через login-shell
  (`/bin/zsh -lic 'command -v …'`) + `--version`; не найдено → показывает команды
  установки/авторизации (копируются). Выбор «агента по умолчанию».

### Доски (Space / Board) — мудборд-холст
- Вход: вкладка **Boards** в верхнем меню (третья вкладка) — общая коллекция
  всех досок пользователя, карточками; кнопка «New board» (`NewBoardSheet`),
  открытие по клику, правый клик — дублировать/удалить.
- Доски глобальные (не привязаны к группировке). Модели `Board` и `BoardItem` в
  `BoardModels.swift`; поле `Board.projectName` оставлено в модели, но в UI не
  используется (создаются с пустым значением).
- `BoardView` — экран доски: тёмный холст с точечной сеткой, пан/зум (жесты +
  кнопки «− % +» + скролл/пинч), камера сохраняется в `Board`.
- Элементы (`BoardItem`): картинки из библиотеки (ссылка по `assetID`), заметки,
  текст, фигуры (rectangle/ellipse/triangle/line/arrow/elbow), фреймы.
- Левый тулбар (`BoardToolbar`): Select, Add image, Note, Text, Shapes (флайаут),
  Frame, Undo/Redo, Export. Панель действий над элементом (`BoardSelectionToolbar`):
  duplicate, copy, на передний/задний план, lock, delete. Форматирование текста —
  `BoardTextToolbar`. Выбор картинок — `BoardLibraryPanel` (мультивыбор).
- Undo/redo — снимки раскладки (`BoardItemSnapshot`). Экспорт доски в PNG —
  `ImageRenderer` (`BoardExportView`), без сетки и тулбаров.
- Горячие клавиши: V/R/E/Y/L/A/B (инструменты), ⌘Z/⌘⇧Z (undo/redo), Delete, Esc.
- Состояние одной открытой доски держит `BoardViewModel` (камера, инструмент,
  выделение, история). Удалённый из библиотеки ассет молча убирается с доски.

---

## 3. Roadmap (приоритеты MVP → дальше)

### MVP (для выкладки на GitHub)
- [x] Библиотека с типами: изображения, видео, гифки, ссылки, сниппеты
- [x] Цветовой фильтр, поиск, сортировка
- [x] Detail view с промптами, заметками, тегами
- [x] Типы skill и mcpServer
- [x] Projects + экспорт context pack
- [x] CI: GitHub Actions собирает приложение на каждый push (`.github/workflows/build.yml`)
- [ ] README.md для GitHub (скриншоты, описание, сборка)
- [ ] Иконка приложения и финальный полиш

### После MVP
- [ ] Many-to-many: ассет в нескольких проектах/коллекциях
- [x] Canvas-доска внутри проекта (мудборд, как Milanote) — **реализовано
      по фазам 1–9 из `SPACE_BOARD_SPEC.md`** (см. раздел «Доски» ниже).
      На будущее: снапы/направляющие, захват детей фреймом, lightweight-миграция БД
- [x] Подключение AI-провайдеров (окно настроек: API-ключи в Keychain, Test
      connection, CLI-агенты) — см. раздел «Настройки». Осталось подключить сами
      фичи к ключам:
- [ ] AI-фичи поверх подключённых провайдеров: «Generate variation», auto-tag
      через vision-модель, генерация context.md через LLM
- [ ] Импорт скиллов/MCP-конфигов из папок `~/.claude/` автоматически
- [ ] Шаблоны проектов («лендинг», «телеграм-бот» — преднаполненные паки)
- [ ] Quick Look (Space), Spotlight-индексация
- [ ] Экспорт прямо в git-репозиторий / gh CLI

### Идеи (бэклог)
- Версионирование промптов; история изменений
- Шаринг паков между пользователями (экспорт/импорт .manatherpack)
- Горячая клавиша глобального «быстрого сохранения» из любого приложения
- Браузерное расширение для сохранения референсов в один клик

---

## 4. Технические правила

- **macOS 14+, SwiftUI + SwiftData**, проект собирается с `-default-isolation=MainActor`
  (Swift 5 mode + upcoming features) — не использовать `Task.detached` с не-Sendable
  типами без необходимости
- **App Sandbox ОТКЛЮЧЁН** (`ENABLE_APP_SANDBOX = NO`, `manather.entitlements`).
  Осознанное решение: нужно детектить/запускать внешние CLI-агенты (`Process`) и
  читать их конфиги. Несовместимо с Mac App Store, но ок для GitHub/DMG. Следствие:
  у приложения полный доступ к файлам/процессам — обращаться с этим аккуратно
  (запуск CLI и т.п. — только по действию пользователя, команды из фикс-списка).
- Сборка (из корня репозитория, где лежит `manather.xcodeproj`):
  `xcodebuild -project manather.xcodeproj -scheme manather -destination 'platform=macOS' build`
- **Нет Мака под рукой? Проверяй сборку через CI**: любой push в ветку запускает
  GitHub Actions (`.github/workflows/build.yml`, раннер `macos-26`) и собирает проект.
  Зелёная галочка = компилируется. Это основной способ верификации без Mac.
- Xcode-проект использует FileSystemSynchronized groups — новые .swift-файлы в
  `manather/` подхватываются автоматически
- Для сетки — только кешированные тамбнейлы (`CachedImageView`), никогда не декодировать
  оригиналы; `CachedImageView` отслеживает `loadedPath` (фикс залипания превью — не ломать)
- Дизайн: светлая тема — белый/бумажный фон, чёрная капсула активного таба;
  тёмная — нейтральный графит (НЕ синий/teal); скругления карточек 12, панелей 16
- Все строки UI на английском; комментарии в коде на английском
- Владелец проекта — не разработчик: объясняй изменения простым языком, избегай жаргона

## 5. Структура файлов

`manather.xcodeproj` лежит в корне репозитория; исходники — в папке `manather/`.

```
manather/
├── manatherApp.swift            — точка входа, ModelContainer (+ восстановление БД, зум-команды)
├── ContentView.swift            — корневой вью, тема (ManatherTheme), кривые анимации, UI-зум
├── AssetItem.swift              — SwiftData-модель ассета + AssetType
├── AssetCollection.swift        — SwiftData-модель коллекции (реальный объект)
├── NewCollectionSheet.swift     — диалог создания коллекции (название)
├── CollectionFolderCard.swift   — карточка коллекции: «веер» квадратных превью,
│                                   расходится при наведении (hover spread)
├── GalleryGridView.swift        — главный экран: тулбар, masonry, фильтры, импорт, контекст-меню
├── AssetCardView.swift          — карточка ассета (все типы)
├── AssetDetailView.swift        — полноэкранный просмотр + навигация
├── InspectorView.swift          — правая панель метаданных (промпт, теги, chips)
├── CachedImageView.swift        — async-загрузка изображений с кешем
├── FileManagerHelper.swift      — файлы, ImageCache, DominantColorExtractor
├── ColorIndex.swift             — 7 цветовых корзин, классификация, последовательная индексация
├── CustomContextMenu.swift      — правый клик: ловец + тёмное меню (AssetContextMenuView)
├── MicroAnimationButtonStyle.swift — стиль кнопок с микро-анимацией нажатия
├── ContextPackExporter.swift    — экспорт коллекции в build pack (двухуровневый бриф)
├── ExportGoalSheet.swift        — окно ввода цели проекта перед экспортом
├── SettingsView.swift           — модальное окно настроек (вкладки General/AI/CLI/About)
├── AIProvider.swift             — каталог AI-провайдеров (метаданные)
├── AIProviderStore.swift        — стор ключей/моделей + ProviderConnectionService (Test)
├── KeychainStore.swift          — безопасное хранение секретов в Keychain
├── CLIAgent.swift               — каталог CLI-агентов + детектор установки
├── AddWebLinkSheet.swift        — добавление ссылки
├── AddCodeSnippetSheet.swift    — добавление сниппета
├── AddMCPServerSheet.swift      — добавление MCP-сервера
├── AddSkillSheet.swift          — добавление скилла
├── AnimatedGifView.swift        — покадровое проигрывание GIF
├── VisualEffectView.swift       — обёртка NSVisualEffectView (блюр-материалы)
├── WebView.swift                — обёртка WKWebView для webLink
├── WebsiteScreenshotManager.swift — скриншоты веб-страниц (WebKit)
│
│   — Доски (Space / Board):
├── BoardModels.swift            — модели Board, BoardItem, enums, BoardItemSnapshot
├── BoardViewModel.swift         — состояние открытой доски (камера, инструмент, undo)
├── NewBoardSheet.swift          — диалог создания доски (название + описание)
├── BoardView.swift              — экран доски: топ-бар, тулбары, экспорт PNG, хоткеи
├── BoardCanvasView.swift        — холст: сетка, пан/зум, рендер элементов, рисование
├── BoardItemView.swift          — рендер элемента (image/note/text/shape/frame) + ресайз
├── BoardToolbar.swift           — левая панель инструментов + флайаут фигур
├── BoardSelectionToolbar.swift  — плавающая панель действий над выделенным элементом
├── BoardTextToolbar.swift       — панель форматирования текста/заметки
├── BoardLibraryPanel.swift      — правая панель выбора картинок (мультивыбор)
└── BoardExportView.swift        — статичный рендер доски для PNG-экспорта
```

CI: `.github/workflows/build.yml` — сборка на каждый push (раннер `macos-26`).

## 6. Релизы (DMG)

`.github/workflows/release.yml` собирает Release-сборку, пакует `.dmg` и публикует
GitHub Release **при пуше тега `v*`** (имя DMG и заголовок берутся из тега; текст
релиза — из секции `## [X.Y.Z]` в `CHANGELOG.md`). Процесс выпуска новой версии:

1. **Узнай реальную последнюю версию через УДАЛЁННЫЕ теги, а не локальные:**
   `git ls-remote --tags origin`. ⚠️ `git tag` показывает только локальные теги —
   они часто устаревшие (новые теги/релизы могли создать без тебя), и можно
   ошибочно выбрать уже занятый номер. (Реальный случай: локально максимум был
   `v0.1.3`, а на удалёнке уже жил выпущенный `v0.1.4` — следующая версия 0.1.5.)
2. Подними `MARKETING_VERSION` в `manather.xcodeproj/project.pbxproj` (две строки,
   Debug+Release) до новой версии.
3. Добавь секцию `## [X.Y.Z] — YYYY-MM-DD` в начало `CHANGELOG.md` (под `[Unreleased]`).
4. Закоммить, запушь `main`, затем `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. Проверь сборку: `curl -s https://api.github.com/repos/Manath-iq/Manather/actions/runs?per_page=3`
   (поле `conclusion`) и релиз: `.../releases/latest` (ассет `.dmg`). `gh` НЕ установлен —
   используй GitHub API через curl (репозиторий публичный, токен не нужен для чтения).
