using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using LabelStudio.App.Models;
namespace LabelStudio.App.Services;
public static class LabelVisualFactory
{
    public const double DipPerMm = 96.0 / 25.4;
    public static FrameworkElement CreateItem(LabelItem item, IReadOnlyDictionary<string,string>? record = null)
    {
        FrameworkElement visual;
        if (item.Kind == "Box")
            visual = new Border { Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm, BorderBrush=Brushes.Black, BorderThickness=new Thickness(Math.Max(0.2,item.StrokeMm)*DipPerMm) };
        else if (item.Kind == "Ellipse")
            visual = new Ellipse { Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm, Stroke=Brushes.Black, StrokeThickness=Math.Max(0.2,item.StrokeMm)*DipPerMm };
        else if (item.Kind == "Line")
            visual = new Line { X1=0,Y1=0,X2=item.WidthMm*DipPerMm,Y2=item.HeightMm*DipPerMm, Stroke=Brushes.Black, StrokeThickness=Math.Max(0.2,item.StrokeMm)*DipPerMm, Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm };
        else
        {
        var value = item.Value;
        if (!string.IsNullOrWhiteSpace(item.DataField) && record is not null && record.TryGetValue(item.DataField, out var data)) value=data;
        visual = new TextBlock
        {
            Text=value, FontFamily=new FontFamily("Arial"), FontSize=item.FontSizePt*96.0/72.0,
            FontWeight=item.Bold ? FontWeights.Bold : FontWeights.Normal,
            Foreground=Brushes.Black, TextWrapping=TextWrapping.Wrap,
            Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm,
            ClipToBounds=true
        };
        }
        visual.RenderTransformOrigin=new Point(0.5,0.5);
        visual.RenderTransform=new RotateTransform(item.RotationDeg);
        return visual;
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
