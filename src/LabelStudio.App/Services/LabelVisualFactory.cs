using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using LabelStudio.App.Models;
namespace LabelStudio.App.Services;
public static class LabelVisualFactory
{
    public const double DipPerMm = 96.0 / 25.4;
    public static FrameworkElement CreateItem(LabelItem item, IReadOnlyDictionary<string,string>? record = null)
    {
        if (item.Kind == "Box") return new Border { Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm, BorderBrush=Brushes.Black, BorderThickness=new Thickness(1) };
        var value = item.Value;
        if (!string.IsNullOrWhiteSpace(item.DataField) && record is not null && record.TryGetValue(item.DataField, out var data)) value=data;
        return new TextBlock
        {
            Text=value, FontFamily=new FontFamily("Arial"), FontSize=item.FontSizePt*96.0/72.0,
            FontWeight=item.Bold ? FontWeights.Bold : FontWeights.Normal,
            Foreground=Brushes.Black, TextWrapping=TextWrapping.Wrap,
            Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm,
            ClipToBounds=true
        };
    }
    public static Canvas CreateCanvas(LabelDocument doc, IReadOnlyDictionary<string,string>? record=null)
    {
        var canvas = new Canvas { Width=doc.WidthMm*DipPerMm, Height=doc.HeightMm*DipPerMm, Background=Brushes.White };
        foreach(var item in doc.Items)
        {
            var visual=CreateItem(item,record);
            Canvas.SetLeft(visual,item.Xmm*DipPerMm); Canvas.SetTop(visual,item.Ymm*DipPerMm);
            canvas.Children.Add(visual);
        }
        return canvas;
    }
}
