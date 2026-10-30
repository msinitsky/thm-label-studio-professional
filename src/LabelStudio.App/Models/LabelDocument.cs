using System.Text.Json.Serialization;
namespace LabelStudio.App.Models;
public sealed class LabelDocument
{
    public string Name { get; set; } = "New label";
    public double WidthMm { get; set; } = 60;
    public double HeightMm { get; set; } = 30;
    public List<LabelItem> Items { get; set; } = new();
}
public sealed class LabelItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Kind { get; set; } = "Text"; // Text, Box, Ellipse, Line, QR, Code128, Image
    public string Value { get; set; } = "Text";
    public string? DataField { get; set; }
    public string? ImageDataBase64 { get; set; } // Embedded PNG/JPEG/BMP; portable JSON templates
    public string? ImageDataBase64 { get; set; } // Embedded PNG/JPEG/BMP; portable JSON templates
    public string? ImageDataBase64 { get; set; } // Embedded PNG/JPEG/BMP; portable JSON templates
    public double Xmm { get; set; } = 5;
    public double Ymm { get; set; } = 5;
    public double WidthMm { get; set; } = 20;
    public double HeightMm { get; set; } = 7;
    public double FontSizePt { get; set; } = 12;
    public bool Bold { get; set; }
    public double RotationDeg { get; set; }
    public double StrokeMm { get; set; } = 0.25;
}
