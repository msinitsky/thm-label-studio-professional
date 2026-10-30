# Сборка Windows-приложения в GitHub Actions

Этот архив содержит исходный проект и файл `.github/workflows/windows-build.yml`. Проект **ещё не является полным аналогом BarTender**: пока работает базовый редактор и печать через драйвер Windows. Адаптеры THM RAW, ZPL, TSPL, CAB, Godex и пакетная печать в этой C#-версии пока не реализованы.

## Пошагово — без Visual Studio

1. Войдите в https://github.com и создайте **новый пустой репозиторий** через **New repository**. Например, `thm-label-studio-professional`. Выберите **Private**. Не добавляйте README, .gitignore или лицензию при создании.
2. Распакуйте ZIP на компьютер. В полученной папке должны быть `src`, `.github`, `THM_Label_Studio_Professional.slnx`, `sample.csv` и другие файлы.
3. На GitHub откройте новый репозиторий → **uploading an existing file / Add file → Upload files**. Перетащите **содержимое папки**, включая скрытую `.github`, сохраняя пути. ВНИМАНИЕ: через веб-загрузку GitHub вложенная структура папок, особенно `.github`, может загрузиться не так, как ожидается. Надёжнее использовать вариант `git` ниже.
4. **Рекомендуемый надёжный способ через PowerShell с установленным Git for Windows**, находясь в распакованной папке:

```powershell
git init
git branch -M main
git add .
git commit -m "Initial Windows build"
git remote add origin https://github.com/ВАШ_ЛОГИН/thm-label-studio-professional.git
git push -u origin main
```

При входе Git может предложить авторизацию через браузер. Используйте свой аккаунт GitHub; токены в чат не присылайте.

5. На странице репозитория GitHub откройте **Actions** → при необходимости разрешите workflows → **Build Windows x64** → **Run workflow** → **Run workflow**.
6. Откройте завершённый запуск с зелёной галочкой. Внизу страницы в разделе **Artifacts** скачайте `THM-Label-Studio-Professional-Windows-x64`.
7. Распакуйте скачанный архив и запустите **LabelStudio.App.exe**. SDK и Visual Studio на компьютере пользователя не требуются: .NET опубликован совместно с приложением.

Если Actions недоступны, проверьте настройки репозитория, разрешение Actions и лимиты GitHub для вашего аккаунта. **Сборка через облако не выполнялась в этой среде**; при первом запуске workflow может обнаружиться ошибка компиляции, тогда пришлите текст лога `Publish portable Windows executable`.

## Альтернатива — на своём Windows ПК

Установите .NET 10 SDK, затем откройте PowerShell в папке проекта и запустите:

```powershell
powershell -ExecutionPolicy Bypass -File .\BUILD_WINDOWS.ps1
```

Готовый файл будет в `dist\LabelStudioProfessional\LabelStudio.App.exe`.

## Важные ограничения

- Публикация single-file/self-contained не означает, что каждый файл (например PDB или ресурсы) обязательно находится внутри единственного EXE. Храните содержимое скачанной папки вместе.
- Исполняемый файл не имеет цифровой подписи издателя; Windows SmartScreen может выдавать предупреждение о неизвестном издателе.
- Состояние принтера и реальную печать проверять на устройстве; успешная сборка гарантирует только компиляцию и наличие EXE.
- Для репозитория GitHub не загружайте USB-захваты, секреты, частные файлы и данные производственной маркировки, не предназначенные для хранения в облаке. В текущем пакете есть два учебных RAW-образца и эталонный PowerShell-код в `legacy-reference`.
