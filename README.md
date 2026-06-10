# Manather (macOS Application)

[Русская версия ниже](#ru-описание-приложения-manather)

Manather is a native, intelligent desktop gallery for developers, designers, and AI enthusiasts. It is designed to organize, store, and manage visual references, interface screenshots, code snippets, web links, and their associated metadata (such as generation prompts, source URLs, and personal notes).

The application is built with a local-first philosophy, utilizing Apple's modern frameworks for high performance, smooth animations, and sandbox compliance.

---

## Key Features

1. **Multi-Format Assets**: Organize static images, animated GIFs, web links, and syntax-highlighted code snippets in a single visual workspace.
2. **Headless Web Screenshotting**: When importing web links, the application uses an off-screen `WKWebView` to automatically render and save a high-quality preview screenshot.
3. **Color Palette Extraction**: Automatically extracts the dominant color palette (up to 8 colors) from imported images and allows copying HEX codes to the clipboard in one click.
4. **Metadata Inspector**: A fully integrated side panel that allows viewing and editing details like Titles, Source URLs, Space/Collection groupings, Notes, and AI Prompts.
5. **Interactive Grid**: A responsive grid layout supporting dynamic column resizing (from 2 to 6 columns) with fluid spring animations.
6. **Local Sandbox Architecture**: Files are copied directly into the app's secure container (Application Support), storing only relative paths in the SwiftData database to prevent performance degradation and memory bloating.

---

## Technical Stack

* **Language**: Swift 5.10 / Swift 6
* **UI Framework**: SwiftUI (utilizing native macOS patterns, responsive split views, and micro-animations)
* **Database**: SwiftData (local persistence container)
* **Web Integration**: WebKit (`WKWebView` snapshot rendering)
* **OS Target**: macOS 14.0 Sonoma and newer

---

## Local Development & Setup

### Requirements
* macOS Sonoma (14.0) or higher
* Xcode 15.0 or higher

### Building the App
1. Clone the repository:
   ```bash
   git clone https://github.com/Manath-iq/Manather.git
   ```
2. Open `manather.xcodeproj` in Xcode.
3. Select the `manather` scheme.
4. Select **Product > Build** (Cmd+B) or **Product > Run** (Cmd+R) to compile and launch the application locally.

---

<br>

# RU: Описание приложения "Manather"

**Manather** — это интеллектуальная десктопная галерея для разработчиков, дизайнеров и ИИ-энтузиастов, предназначенная для упорядоченного хранения визуальных референсов, скриншотов интерфейсов, фрагментов кода, веб-ссылок и сопутствующих метаданных (включая промпты генерации и текстовые заметки).

Приложение разработано на базе локальной архитектуры (local-first) с использованием современных фреймворков Apple, что гарантирует высокую производительность, плавные анимации и безопасность данных в рамках песочницы macOS.

---

## Основные возможности

1. **Мультиформатность**: Хранение статических картинок, GIF-анимаций, веб-ссылок и фрагментов кода с поддержкой подсветки синтаксиса в одной единой сетке.
2. **Фоновые скриншоты сайтов**: При добавлении веб-ссылки приложение автоматически рендерит страницу в скрытом компоненте `WKWebView` и сохраняет её графический снимок как превью.
3. **Генерация цветовой палитры**: Автоматический разбор изображения на 8 доминантных цветов с возможностью копирования HEX-кода цвета в буфер обмена в один клик.
4. **Инспектор метаданных**: Удобная боковая панель для редактирования названий, веб-адресов, коллекций/пространств, личных заметок и ИИ-промптов.
5. **Адаптивная сетка**: Динамическое масштабирование количества колонок (от 2 до 6) с плавными интерактивными эффектами.
6. **Песочница и файловая система**: Все бинарные файлы копируются во внутреннюю директорию приложения (Application Support), а база данных SwiftData хранит только относительные пути, исключая замедление работы приложения и разрастание базы данных.

---

## Технологический стек

* **Язык**: Swift 5.10 / Swift 6
* **Интерфейс**: SwiftUI (с нативными гайдлайнами macOS, NavigationSplitView и микро-анимациями)
* **Хранилище данных**: SwiftData (локальная база данных)
* **Рендеринг**: WebKit (фоновое создание скриншотов через WKSnapshotConfiguration)
* **Поддерживаемая ОС**: macOS 14.0 Sonoma и новее

---

## Локальная сборка и запуск

### Требования
* macOS Sonoma (14.0) или более новая версия
* Xcode 15.0 или выше

### Шаги для сборки
1. Склонируйте репозиторий:
   ```bash
   git clone https://github.com/Manath-iq/Manather.git
   ```
2. Откройте файл `manather.xcodeproj` в Xcode.
3. Убедитесь, что выбран таргет `manather`.
4. Нажмите **Product > Build** (Cmd+B) для компиляции или **Product > Run** (Cmd+R) для запуска приложения на вашем Mac.
