using System.IO;
using System.Text.Json;
using LabelStudio.App.Models;
namespace LabelStudio.App.Services;
public static class DocumentStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    public static void Save(string path, LabelDocument doc) => File.WriteAllText(path, JsonSerializer.Serialize(doc, Options));
    public static LabelDocument Load(string path)
    {
        var doc = JsonSerializer.Deserialize<LabelDocument>(File.ReadAllText(path), Options) ?? throw new InvalidDataException("Empty document");
        if (doc.WidthMm <= 0 || doc.HeightMm <= 0 || doc.WidthMm > 1000 || doc.HeightMm > 1000)
            throw new InvalidDataException("Label size must be between 0 and 1000 mm");
        doc.Items ??= new();
        return doc;
    }
}
