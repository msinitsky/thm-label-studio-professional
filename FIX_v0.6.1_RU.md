# Исправление v0.6.1

Исправлены дублирующиеся определения методов MakeBarcodeVisual и MakeImageVisual, дублированные using и переменная value в LabelVisualFactory.cs, тройное объявление ImageDataBase64 в LabelDocument.cs, трижды повторённая зависимость ZXing.Net в csproj. Также исправлено сохранение встроенного изображения при дублировании объекта.

Проект проверен статически, включая валидность XML, и предназначен для компиляции GitHub Actions. Компиляция на Windows в текущей среде не выполнялась.

Распакуйте поверх Git-репозитория, сохранив .git, затем:

```powershell
git add -A
git commit -m "Fix duplicate declarations in Ribbon v0.6.1"
git push origin main
```

Если GitHub Actions покажет новые ошибки, предоставьте первый блок сообщений с указанием строк.
