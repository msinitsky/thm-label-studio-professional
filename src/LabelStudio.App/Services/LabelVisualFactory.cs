using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Media.Imaging;
using System.IO;
using ZXing;
using ZXing.Common;
using ZXing.QrCode;
using System.Windows.Media.Imaging;
using System.IO;
using ZXing;
using ZXing.Common;
using ZXing.QrCode;
using System.Windows.Media.Imaging;
using System.IO;
using ZXing;
using ZXing.Common;
using ZXing.QrCode;
using LabelStudio.App.Models;
namespace LabelStudio.App.Services;
public static class LabelVisualFactory
{
    public const double DipPerMm = 96.0 / 25.4;
    public static FrameworkElement CreateItem(LabelItem item, IReadOnlyDictionary<string,string>? record = null)
    {
        var value = item.Value;
        if (!string.IsNullOrWhiteSpace(item.DataField) && record is not null && record.TryGetValue(item.DataField, out var data)) value=data;
        var value = item.Value;
        if (!string.IsNullOrWhiteSpace(item.DataField) && record is not null && record.TryGetValue(item.DataField, out var data)) value=data;
        var value = item.Value;
        if (!string.IsNullOrWhiteSpace(item.DataField) && record is not null && record.TryGetValue(item.DataField, out var data)) value=data;
        FrameworkElement visual;
        if (item.Kind == "Box")
            visual = new Border { Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm, BorderBrush=Brushes.Black, BorderThickness=new Thickness(Math.Max(0.2,item.StrokeMm)*DipPerMm) };
        else if (item.Kind == "Ellipse")
            visual = new Ellipse { Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm, Stroke=Brushes.Black, StrokeThickness=Math.Max(0.2,item.StrokeMm)*DipPerMm };
        else if (item.Kind == "Line")
            visual = new Line { X1=0,Y1=0,X2=item.WidthMm*DipPerMm,Y2=item.HeightMm*DipPerMm, Stroke=Brushes.Black, StrokeThickness=Math.Max(0.2,item.StrokeMm)*DipPerMm, Width=item.WidthMm*DipPerMm, Height=item.HeightMm*DipPerMm };
        else if (item.Kind == "QR" || item.Kind == "Code128")
        {
            visual = MakeBarcodeVisual(item, value);
        }
        else if (item.Kind == "Image")
        {
            visual = MakeImageVisual(item);
        }
        else
        {
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
    private static FrameworkElement MakeBarcodeVisual(LabelItem item, string value)
    {
        double w = Math.Max(1, item.WidthMm * DipPerMm);
        double h = Math.Max(1, item.HeightMm * DipPerMm);
        if (string.IsNullOrWhiteSpace(value)) return new Border { Width=w, Height=h };
        try
        {
            bool qr = item.Kind == "QR";
            // Generate at printer-like raster resolution; keep QR square and provide a quiet zone.
            int pixelsW = Math.Clamp((int)Math.Round(item.WidthMm * 12), 90, 4096);
            int pixelsH = Math.Clamp((int)Math.Round(item.HeightMm * 12), 60, 4096);
            if (qr) pixelsW = pixelsH = Math.Max(pixelsW,pixelsH);
            var writer = new ZXing.BarcodeWriterPixelData
            {
                Format = qr ? BarcodeFormat.QR_CODE : BarcodeFormat.CODE_128,
                Options = qr
                    ? new QrCodeEncodingOptions { Width=pixelsW, Height=pixelsH, Margin=4, CharacterSet="UTF-8" }
                    : new EncodingOptions { Width=pixelsW, Height=pixelsH, Margin=8, PureBarcode=true }
            };
            var image = writer.Write(value);
            var bitmap = BitmapSource.Create(image.Width,image.Height,96,96,PixelFormats.Bgra32,null,image.Pixels,image.Width*4);
            bitmap.Freeze();
            return new Image { Width=w, Height=h, Source=bitmap, Stretch=Stretch.Uniform, SnapsToDevicePixels=true };
        }
        catch (Exception ex)
        {
            return new TextBlock { Width=w, Height=h, Foreground=Brushes.DarkRed,
                Text="Ошибка кода: " + ex.Message, TextWrapping=TextWrapping.Wrap, FontSize=9 };
        }
    }
    private static FrameworkElement MakeImageVisual(LabelItem item)
    {
        double w=Math.Max(1,item.WidthMm*DipPerMm), h=Math.Max(1,item.HeightMm*DipPerMm);
        if (string.IsNullOrWhiteSpace(item.ImageDataBase64))
            return new Border { Width=w,Height=h,BorderBrush=Brushes.DarkGray,BorderThickness=new Thickness(1) };
        try
        {
            byte[] bytes=Convert.FromBase64String(item.ImageDataBase64);
            using var stream=new MemoryStream(bytes);
            var bitmap=new BitmapImage();
            bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.StreamSource=stream;bitmap.EndInit();
            bitmap.Freeze();
            return new Image { Width=w,Height=h,Source=bitmap,Stretch=Stretch.Uniform,SnapsToDevicePixels=true };
        }
        catch (Exception)
        {
            return new TextBlock { Width=w,Height=h,Text="Изображение повреждено",Foreground=Brushes.DarkRed };
        }
    }
    private static FrameworkElement MakeBarcodeVisual(LabelItem item, string value)
    {
        double w = Math.Max(1, item.WidthMm * DipPerMm);
        double h = Math.Max(1, item.HeightMm * DipPerMm);
        if (string.IsNullOrWhiteSpace(value)) return new Border { Width=w, Height=h };
        try
        {
            bool qr = item.Kind == "QR";
            // Generate at printer-like raster resolution; keep QR square and provide a quiet zone.
            int pixelsW = Math.Clamp((int)Math.Round(item.WidthMm * 12), 90, 4096);
            int pixelsH = Math.Clamp((int)Math.Round(item.HeightMm * 12), 60, 4096);
            if (qr) pixelsW = pixelsH = Math.Max(pixelsW,pixelsH);
            var writer = new ZXing.BarcodeWriterPixelData
            {
                Format = qr ? BarcodeFormat.QR_CODE : BarcodeFormat.CODE_128,
                Options = qr
                    ? new QrCodeEncodingOptions { Width=pixelsW, Height=pixelsH, Margin=4, CharacterSet="UTF-8" }
                    : new EncodingOptions { Width=pixelsW, Height=pixelsH, Margin=8, PureBarcode=true }
            };
            var image = writer.Write(value);
            var bitmap = BitmapSource.Create(image.Width,image.Height,96,96,PixelFormats.Bgra32,null,image.Pixels,image.Width*4);
            bitmap.Freeze();
            return new Image { Width=w, Height=h, Source=bitmap, Stretch=Stretch.Uniform, SnapsToDevicePixels=true };
        }
        catch (Exception ex)
        {
            return new TextBlock { Width=w, Height=h, Foreground=Brushes.DarkRed,
                Text="Ошибка кода: " + ex.Message, TextWrapping=TextWrapping.Wrap, FontSize=9 };
        }
    }
    private static FrameworkElement MakeImageVisual(LabelItem item)
    {
        double w=Math.Max(1,item.WidthMm*DipPerMm), h=Math.Max(1,item.HeightMm*DipPerMm);
        if (string.IsNullOrWhiteSpace(item.ImageDataBase64))
            return new Border { Width=w,Height=h,BorderBrush=Brushes.DarkGray,BorderThickness=new Thickness(1) };
        try
        {
            byte[] bytes=Convert.FromBase64String(item.ImageDataBase64);
            using var stream=new MemoryStream(bytes);
            var bitmap=new BitmapImage();
            bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.StreamSource=stream;bitmap.EndInit();
            bitmap.Freeze();
            return new Image { Width=w,Height=h,Source=bitmap,Stretch=Stretch.Uniform,SnapsToDevicePixels=true };
        }
        catch (Exception)
        {
            return new TextBlock { Width=w,Height=h,Text="Изображение повреждено",Foreground=Brushes.DarkRed };
        }
    }
    private static FrameworkElement MakeBarcodeVisual(LabelItem item, string value)
    {
        double w = Math.Max(1, item.WidthMm * DipPerMm);
        double h = Math.Max(1, item.HeightMm * DipPerMm);
        if (string.IsNullOrWhiteSpace(value)) return new Border { Width=w, Height=h };
        try
        {
            bool qr = item.Kind == "QR";
            // Generate at printer-like raster resolution; keep QR square and provide a quiet zone.
            int pixelsW = Math.Clamp((int)Math.Round(item.WidthMm * 12), 90, 4096);
            int pixelsH = Math.Clamp((int)Math.Round(item.HeightMm * 12), 60, 4096);
            if (qr) pixelsW = pixelsH = Math.Max(pixelsW,pixelsH);
            var writer = new ZXing.BarcodeWriterPixelData
            {
                Format = qr ? BarcodeFormat.QR_CODE : BarcodeFormat.CODE_128,
                Options = qr
                    ? new QrCodeEncodingOptions { Width=pixelsW, Height=pixelsH, Margin=4, CharacterSet="UTF-8" }
                    : new EncodingOptions { Width=pixelsW, Height=pixelsH, Margin=8, PureBarcode=true }
            };
            var image = writer.Write(value);
            var bitmap = BitmapSource.Create(image.Width,image.Height,96,96,PixelFormats.Bgra32,null,image.Pixels,image.Width*4);
            bitmap.Freeze();
            return new Image { Width=w, Height=h, Source=bitmap, Stretch=Stretch.Uniform, SnapsToDevicePixels=true };
        }
        catch (Exception ex)
        {
            return new TextBlock { Width=w, Height=h, Foreground=Brushes.DarkRed,
                Text="Ошибка кода: " + ex.Message, TextWrapping=TextWrapping.Wrap, FontSize=9 };
        }
    }
    private static FrameworkElement MakeImageVisual(LabelItem item)
    {
        double w=Math.Max(1,item.WidthMm*DipPerMm), h=Math.Max(1,item.HeightMm*DipPerMm);
        if (string.IsNullOrWhiteSpace(item.ImageDataBase64))
            return new Border { Width=w,Height=h,BorderBrush=Brushes.DarkGray,BorderThickness=new Thickness(1) };
        try
        {
            byte[] bytes=Convert.FromBase64String(item.ImageDataBase64);
            using var stream=new MemoryStream(bytes);
            var bitmap=new BitmapImage();
            bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.StreamSource=stream;bitmap.EndInit();
            bitmap.Freeze();
            return new Image { Width=w,Height=h,Source=bitmap,Stretch=Stretch.Uniform,SnapsToDevicePixels=true };
        }
        catch (Exception)
        {
            return new TextBlock { Width=w,Height=h,Text="Изображение повреждено",Foreground=Brushes.DarkRed };
        }
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
