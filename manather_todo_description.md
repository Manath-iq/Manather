# ТЗ: Клон GatherOS — macOS-приложение для визуальных референсов

> Документ составлен для передачи AI-ассистенту (Claude / GPT) с целью разработки нативного macOS-приложения. Описывает все экраны, функции, поведение интерфейса и технический стек.

---

## 1. Продукт

### Что делает приложение

Локальная визуальная библиотека для дизайнеров. Пользователь импортирует изображения, организует их по коллекциям, создаёт мудборды и хранит AI-промпты прямо внутри карточки изображения.

### Аналоги

- Eagle (хранение референсов)
- Pinterest (masonry grid)
- PureRef (мудборды)
- Milanote (canvas-доски)

### Аудитория

UI/UX дизайнеры, бренд-дизайнеры, motion-дизайнеры, AI-художники, маркетологи.

---

## 2. Архитектура окна

```
┌──────────────────────────────────────────────────────────┐
│                      TOOLBAR                             │
│  [+Import]      [Library | Collections | Spaces]  [≡ ⊞] │
├───────────────┬──────────────────────────────────────────┤
│               │                                          │
│   SIDEBAR     │         MAIN CONTENT AREA                │
│   220 px      │         (Masonry Grid / Canvas)          │
│               │                                          │
└───────────────┴──────────────────────────────────────────┘
```

---

## 3. Toolbar

**Высота:** 52 px  
**Стиль:** нативный macOS NSToolbar

### Левая часть — кнопка импорта

- Иконка `+`
- При нажатии — выпадающее меню:
  ```
  Import Images
  Import Folder
  Paste from Clipboard
  ```

### Центр — Segmented Control (переключатель разделов)

```
[ Library ]  [ Collections ]  [ Spaces ]
```

- Активная вкладка: чёрная капсула, белый текст
- Неактивная: прозрачный фон, серый текст
- Переключение: плавная анимация fade + slide, 200 ms

### Правая часть

| Элемент | Описание |
|---|---|
| Строка поиска | Placeholder: `Search...` Поиск по имени, тегам, заметкам, промптам |
| Grid Size Slider | Слайдер изменения размера превью. Min: 6–7 колонок, Max: 2–3 колонки. Real-time. |
| Sort Dropdown | Варианты: `Most Recent`, `Oldest`, `Name A–Z`, `Name Z–A` |
| Overflow меню `...` | `Settings`, `Export Library`, `About` |

---

## 4. Sidebar

**Ширина:** 220 px  
**Фон:** чуть темнее основного контента (vibrancy/translucency)

### Блок навигации (верх)

```
All
Unsorted
Trash
```

- **All** — все элементы библиотеки
- **Unsorted** — элементы без коллекций
- **Trash** — удалённые, с возможностью восстановления

### Блок Collections (список)

Каждая коллекция — карточка:
```
┌─────────────────────────┐
│  [превью 64×64]         │
│  Branding               │
│  34 items               │
└─────────────────────────┘
```

- Правый клик: `Rename`, `Duplicate`, `Delete`, `Export`
- Кнопка `+` снизу — создать коллекцию

---

## 5. Экран Library (главный)

### Layout: Masonry Grid

- Не стандартный LazyVGrid
- Pinterest-style: карточки разной высоты, сохраняющие пропорции изображения
- Количество колонок зависит от слайдера в тулбаре
- Реализация: кастомный `NSCollectionView` или собственный SwiftUI Layout

### Карточка изображения

- Только изображение, без подписей
- Скругление: `12 px`
- **Hover:** масштаб `1.02`, лёгкая тень — анимация 150 ms
- **Double Click:** открыть Detail View
- **Right Click — контекстное меню:**
  ```
  Open
  Copy Prompt
  Add to Collection  ▶  [список коллекций]
  Add to Space       ▶  [список спейсов]
  Duplicate
  Export
  Delete
  ```

### Пустое состояние (Empty Library)

```
[ иконка загрузки ]
Drop images here
or
[ Import your first reference ]
```

---

## 6. Detail View (просмотр элемента)

Открывается в **отдельном окне** (не Sheet, не fullscreen overlay).

### Layout

```
┌─────────────────────────────┬──────────────────────┐
│                             │                      │
│      IMAGE PREVIEW          │   METADATA PANEL     │
│      (масштаб по высоте)    │   340–380 px         │
│                             │                      │
└─────────────────────────────┴──────────────────────┘
```

### Левая часть — Preview

- Изображение масштабируется по высоте окна
- Светлый фон (не чёрный)
- Поддержка Pinch-to-Zoom (trackpad)

### Правая панель — Metadata

**Стиль:** тёмная стеклянная панель (Glassmorphism), скругления `16 px`  
Визуально как macOS Inspector / Xcode Inspector

Блоки сверху вниз:

#### Блок: Image Prompt

```
Image Prompt                          [Copy]
┌────────────────────────────────────┐
│ a futuristic neon cityscape,       │
│ cinematic lighting, 8k, detailed   │
└────────────────────────────────────┘
```

- Многострочное поле, редактируемое
- Кнопка `Copy` — копирует текст промпта в буфер обмена

#### Блок: Collections

```
Collections
[ Branding × ]  [ Typography × ]  [ + Add ]
```

- Каждая коллекция — chip с крестиком
- `+ Add` открывает поиск по существующим коллекциям

#### Блок: Spaces

```
Spaces
[ Untitled board × ]  [ + Add ]
```

#### Блок: Tags

```
Tags
[ abstract ]  [ branding ]  [ ui ]  [ + Add ]
```

- Каждый тег — капсула
- `+ Add` — добавить новый тег (autocomplete по существующим)

#### Блок: Notes

```
Notes
┌────────────────────────────────────┐
│ Add a note...                      │
│                                    │
└────────────────────────────────────┘
```

- Автосохранение, без кнопки Save

---

## 7. AI Variation Panel

Отдельная вкладка или секция в Detail View.

### Элементы

| Элемент | Описание |
|---|---|
| Color Palette | Ряд цветовых кружков — палитра влияния на генерацию |
| Seed Control | Числовое поле или слайдер, диапазон 0–9999 |
| Additional Prompt | Текстовое поле для модификации исходного промпта |
| Кнопка `Generate Variation` | Крупная кнопка. Берёт исходный промпт + параметры → создаёт новое изображение → добавляет в библиотеку |

---

## 8. Экран Collections

Переключается через Segmented Control в тулбаре.

### Сетка коллекций

Равномерный Grid (не Masonry), каждая карточка:
```
┌──────────────────┐
│    [превью]      │
│   Branding       │
│   34 items       │
└──────────────────┘
```

### Создание коллекции

Кнопка `+` → модальное окно:
```
Name:         [ _______________ ]
Cover Image:  [ Choose Image ]

              [ Cancel ]  [ Create ]
```

---

## 9. Экран Spaces (Moodboards)

### Рабочая область

- Бесконечный Canvas (как Figma / Milanote)
- Поддержка: zoom, pan, drag
- Элементы свободно размещаются в любом месте

### Добавление элементов

- Drag & Drop из Library
- Контекстное меню `Add to Space`

### Пустое состояние

```
Drag assets here to start building your moodboard
```

---

## 10. Drag & Drop

| Сценарий | Действие |
|---|---|
| Finder → GatherOS | Импорт изображений напрямую в окно |
| Library → Collection (sidebar) | Добавление в коллекцию |
| Library → Space | Добавление на доску |
| Внутри Space | Перемещение карточек |

**Поддерживаемые форматы:** `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`, `.avif`

---

## 11. Поиск

- Расположение: строка в тулбаре справа
- Поиск по: имени файла, тегам, заметкам, промптам, названию коллекции
- Результат: фильтрация текущей сетки в реальном времени

---

## 12. Горячие клавиши

| Клавиша | Действие |
|---|---|
| `⌘1` | Library |
| `⌘2` | Collections |
| `⌘3` | Spaces |
| `⌘F` | Фокус на поиск |
| `⌘N` | Новая коллекция |
| `⌘⇧N` | Новый Space |
| `⌘⌫` | Удалить в Trash |
| `⌘C` | Копировать промпт (в Detail View) |
| `Space` | Quick Look превью |
| `Esc` | Закрыть Detail View |

---

## 13. Хранение данных

### Структура файлов (локально)

```
~/Library/Application Support/GatherOS/
 ├── Assets/          ← оригинальные изображения
 ├── Thumbnails/      ← превью (генерируются при импорте)
 ├── Spaces/          ← данные canvas-досок
 └── Database.sqlite
```

### База данных SQLite — таблицы

```sql
Assets        (id, filename, path, createdAt, updatedAt)
Prompts       (id, assetId, prompt, seed, colors)
Notes         (id, assetId, content, updatedAt)
Tags          (id, name)
AssetTags     (assetId, tagId)
Collections   (id, name, coverAssetId, createdAt)
AssetCollections (assetId, collectionId)
Spaces        (id, name, createdAt)
SpaceItems    (id, spaceId, assetId, x, y, width, height)
```

> Один Asset может находиться в нескольких Collections и Spaces одновременно — без дублирования файла.

---

## 14. Визуальный стиль

| Параметр | Значение |
|---|---|
| Стиль | Нативный macOS (SwiftUI + AppKit) |
| Шрифт | SF Pro Display (заголовки), SF Pro Text (тело) |
| Скругления карточек | 12 px |
| Скругления панелей | 16–20 px |
| Тема по умолчанию | Светлая |
| Dark Mode | Обязательная поддержка |
| Sidebar фон | `NSVisualEffectView` (Vibrancy) |
| Metadata Panel | Тёмная + Glassmorphism |

### Цветовая схема (светлая тема)

| Роль | Значение |
|---|---|
| Фон основной | `#FFFFFF` |
| Фон sidebar | Vibrancy (системный) |
| Активный сегмент | `#000000` (капсула) |
| Текст активный | `#FFFFFF` |
| Текст неактивный | `#8E8E93` |
| Разделители | `#E5E5EA` |
| Теги/chips | `#F2F2F7` фон, `#1C1C1E` текст |

---

## 15. Анимации

| Событие | Анимация | Длительность |
|---|---|---|
| Переключение вкладок | Fade + Slide | 200 ms |
| Hover карточки | Scale 1.02 + shadow | 150 ms |
| Открытие Detail View | Expand от карточки (как Apple Photos) | 300 ms |
| Импорт изображений | Появление карточек с fade | 200 ms |

---

## 16. macOS-интеграции

- **Quick Look** — `Space` для предпросмотра
- **Finder Drag & Drop** — нативный NSItemProvider
- **Dark Mode** — полная поддержка
- **Menu Bar:** File / Edit / View / Window / Help
- **Spotlight** — индексация метаданных (желательно)
- **Retina** — все изображения в @2x

---

## 17. Технологический стек

| Слой | Технология |
|---|---|
| UI | SwiftUI (основа) + AppKit bridge для сложных компонентов |
| Layout | Кастомный Masonry Layout (NSCollectionView или SwiftUI Layout protocol) |
| База данных | SQLite + GRDB |
| Canvas (Spaces) | SwiftUI + кастомный gesture-обработчик |
| Превью | CoreImage + ImageIO |
| Drag & Drop | NSItemProvider + UniformTypeIdentifiers |
| Quick Look | QuickLook framework |
| Хранение настроек | UserDefaults / SwiftData |

---

## 18. Ключевые технические сложности

1. **Masonry Grid** — самая сложная часть. Нужен кастомный Layout, который расставляет карточки разной высоты по колонкам, как Pinterest.

2. **Бесконечный Canvas (Spaces)** — свободное размещение объектов с zoom/pan, drag-and-drop и сохранением позиций.

3. **Синхронность данных** — один Asset в нескольких Collections/Spaces без дублирования файлов.

4. **Переход из карточки в Detail View** — hero-анимация разворачивания (как в Apple Photos).

---

## 19. Пустые состояния (обязательны для всех экранов)

| Экран | Текст | Действие |
|---|---|---|
| Library | `Drop images here` | Кнопка `Import` |
| Collection | `This collection is empty` | Кнопка `Add Assets` |
| Space | `Drag assets here to start building your moodboard` | — |
| Search | `No results for "..."` | — |
| Trash | `Trash is empty` | — |


---

# РАЗДЕЛ 2: Swift / SwiftUI — Техническая специфика

> Минимальная версия: **macOS 14 Sonoma** (это позволяет использовать актуальный SwiftUI и избежать legacy-костылей)

---

## Архитектура приложения

**Паттерн:** Observable + SwiftData (или GRDB если нужен raw SQL)

```swift
// Точка входа
@main
struct GatherOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            GatherOSCommands() // Menu Bar команды
        }
    }
}
```

**Стейт-менеджмент:** `@Observable` (macOS 14+, замена ObservableObject)

```swift
@Observable
class LibraryStore {
    var assets: [Asset] = []
    var selectedAsset: Asset?
    var searchQuery: String = ""
}
```

---

## Masonry Grid — главная сложность

### Проблема
`LazyVGrid` в SwiftUI не поддерживает разную высоту карточек. Нужен кастомный Layout.

### Решение: кастомный SwiftUI Layout (macOS 14+)

```swift
struct MasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Считаем высоту каждой колонки, распределяем карточки в shortest column
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Расставляем каждую карточку по X/Y
    }
}
```

**Важно нейронке:** НЕ использовать `LazyVStack` с `ForEach` внутри `HStack` — это даёт неправильный порядок при скролле. Только кастомный `Layout`.

### Производительность
Для 1000+ изображений обязательно:
```swift
LazyVStack { } // или ScrollView + LazyLayout
```
Иначе всё загрузится сразу и память ляжет.

---

## Sidebar

### Правильная реализация

```swift
NavigationSplitView {
    SidebarView()
} detail: {
    MainContentView()
}
.navigationSplitViewStyle(.balanced)
```

**Не использовать** HSplitView напрямую — NavigationSplitView даёт нативное поведение macOS (коллапс, ширина, анимации) бесплатно.

---

## Toolbar — Segmented Control по центру

```swift
.toolbar {
    ToolbarItem(placement: .navigation) {
        ImportButton()
    }
    ToolbarItem(placement: .principal) {
        Picker("", selection: $selectedTab) {
            Text("Library").tag(Tab.library)
            Text("Collections").tag(Tab.collections)
            Text("Spaces").tag(Tab.spaces)
        }
        .pickerStyle(.segmented)
        .frame(width: 280)
    }
    ToolbarItemGroup(placement: .automatic) {
        SortMenu()
        GridSlider()
    }
}
```

---

## Detail View — отдельное окно

### Правильный способ открыть второе окно

```swift
// В SwiftUI через openWindow
@Environment(\.openWindow) var openWindow

// Объявить в App
WindowGroup("Detail", for: Asset.ID.self) { $assetId in
    DetailView(assetId: assetId)
}
.defaultSize(width: 900, height: 600)

// Открыть
openWindow(value: asset.id)
```

**Не использовать** sheet или fullScreenCover — это не нативно для macOS.

---

## Hero-анимация (карточка → Detail View)

SwiftUI на macOS **не поддерживает** `.matchedGeometryEffect` между разными окнами.

### Реальные варианты:
1. **Простой fade** — карточка исчезает, новое окно появляется с opacity анимацией. Выглядит прилично.
2. **Zoom из позиции карточки** — кастомная NSWindow анимация через AppKit bridge. Сложно, но даёт эффект как в Photos.
3. **Рекомендация:** начать с варианта 1, потом улучшить.

---

## Drag & Drop — импорт из Finder

```swift
.dropDestination(for: URL.self) { urls, location in
    Task {
        await importImages(from: urls)
    }
    return true
} isTargeted: { isTargeted in
    showDropOverlay = isTargeted
}
```

**Важно:** `URL.self` принимает файлы из Finder автоматически. Фильтровать по UTType:

```swift
import UniformTypeIdentifiers

let allowedTypes: [UTType] = [.jpeg, .png, .webP, .gif, .image]
```

---

## Хранение данных

### Вариант A: SwiftData (проще, macOS 14+)

```swift
@Model
class Asset {
    var id: UUID
    var filename: String
    var relativePath: String
    var createdAt: Date
    var prompt: String?
    var notes: String?
    @Relationship var collections: [Collection]
    @Relationship var tags: [Tag]
}
```

**Плюсы:** интеграция с SwiftUI через `@Query`, автомиграции  
**Минусы:** меньше контроля над SQL, сложные запросы неудобны

### Вариант B: GRDB (мощнее)

```swift
// Полный контроль над SQLite
let dbQueue = try DatabaseQueue(path: dbPath)
let assets = try dbQueue.read { db in
    try Asset.filter(Column("collectionId") == id).fetchAll(db)
}
```

**Плюсы:** быстрее на больших объёмах, сложные JOIN-запросы, FTS (полнотекстовый поиск)  
**Минусы:** больше boilerplate

**Рекомендация:** SwiftData если проект небольшой, GRDB если планируется 10k+ изображений.

---

## Превью / Thumbnails

Генерировать при импорте, не на лету:

```swift
import ImageIO

func generateThumbnail(from url: URL, size: CGSize) async -> NSImage? {
    let options: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * 2, // @2x
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return NSImage(cgImage: cgImage, size: size)
}
```

Сохранять в `Thumbnails/` рядом с оригиналами. Никогда не декодировать оригинал для сетки — только thumbnails.

---

## Spaces — бесконечный Canvas

Самая нетривиальная часть. SwiftUI не имеет встроенного infinite canvas.

### Реализация через ScrollView + ZoomView

```swift
struct InfiniteCanvas: View {
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        Canvas { context, size in
            // Рисуем элементы
        }
        .gesture(
            MagnificationGesture()
                .onChanged { scale = $0 }
        )
        .gesture(
            DragGesture()
                .onChanged { offset = $0.translation }
        )
    }
}
```

**Альтернатива:** использовать `NSScrollView` через `NSViewRepresentable` — даёт более нативное поведение zoom/pan.

---

## Контекстное меню

```swift
.contextMenu {
    Button("Copy Prompt") { copyPrompt() }
    Divider()
    Menu("Add to Collection") {
        ForEach(collections) { collection in
            Button(collection.name) { addToCollection(collection) }
        }
    }
    Divider()
    Button("Delete", role: .destructive) { moveToTrash() }
}
```

---

## Поиск — real-time фильтрация

```swift
var filteredAssets: [Asset] {
    guard !searchQuery.isEmpty else { return assets }
    return assets.filter { asset in
        asset.filename.localizedCaseInsensitiveContains(searchQuery) ||
        asset.prompt?.localizedCaseInsensitiveContains(searchQuery) == true ||
        asset.tags.contains { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }
}
```

Для 10k+ элементов — переносить фильтрацию в background thread через `async`.

---

## Типичные ошибки нейронок в macOS SwiftUI

| Ошибка | Правильно |
|---|---|
| Использует `sheet` для Detail View | `openWindow` — отдельное окно |
| `LazyVGrid` для masonry | Кастомный `Layout` |
| `ObservableObject` | `@Observable` (macOS 14+) |
| Декодирует оригинал для сетки | Только thumbnails |
| Синхронный импорт изображений | `async/await` + `Task` |
| `HSplitView` для sidebar | `NavigationSplitView` |
| `UserDefaults` для хранения ассетов | SQLite / SwiftData |
| Один `@State` для всего стейта | Отдельные `@Observable` stores |

---

## Порядок разработки (рекомендуемый)

1. **Модели данных** (Asset, Collection, Tag, Space) + SQLite/SwiftData
2. **Импорт изображений** + генерация thumbnails
3. **Sidebar** + NavigationSplitView
4. **Masonry Grid** — кастомный Layout
5. **Контекстные меню** + базовые действия
6. **Detail View** — отдельное окно + панель метаданных
7. **Collections экран**
8. **Spaces / Canvas**
9. **Поиск**
10. **Анимации** — в последнюю очередь

