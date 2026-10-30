# Обновление Editor Preview 0.2

1. Закрой запущенную программу.
2. Распакуй содержимое ZIP **поверх** существующей папки `thm-label-studio-professional`, подтвердив замену файлов. Не удаляй `.git`.
3. В PowerShell из папки проекта выполни:

```powershell
git add -A
git commit -m "Editor improvements: shapes, grid, zoom, duplicate"
git push origin main
```

4. Открой https://github.com/msinitsky/thm-label-studio-professional/actions . После завершения Build Windows x64 скачай новый Artifact.
5. Проверь: +Ellipse, +Line, Duplicate, Del, перемещение, 75/100/150/200% и сохранение/открытие JSON.

**Важно:** эта версия не заменяет проверенную программу PowerShell 0.11 для печати на THM MultiMark. Принтерные адаптеры других производителей пока не реализованы.
