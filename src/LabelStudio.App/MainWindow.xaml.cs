using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Controls.Primitives;
using LabelStudio.App.Models;
using LabelStudio.App.Services;
using LabelStudio.App.Printing;
using Microsoft.Win32;
namespace LabelStudio.App;
public partial class MainWindow : Window
{
    private LabelDocument _document = new();
    private LabelItem? _selected;
    private bool _updating;
    private string? _path;
    private List<Dictionary<string,string>> _records = new();
    private int _recordIndex=-1;
    private Point? _dragStart;
    private double _startX, _startY;
    private double _zoom = 1.0;
    private Thumb? _resizeThumb;
    private double _resizeStartW, _resizeStartH;
    private readonly Dictionary<Guid, FrameworkElement> _visuals=new();
    public MainWindow()
    {
        InitializeComponent();
        _document.Items.Add(new LabelItem { Value="SEI-2026", Xmm=5,Ymm=5,WidthMm=38,HeightMm=9,FontSizePt=20,Bold=true });
        RefreshAll();
    }
    private static string F(double v)=>v.ToString("0.##",CultureInfo.InvariantCulture);
    private static bool TryNum(string s,out double n)=>double.TryParse(s.Replace(',','.'),NumberStyles.Float,CultureInfo.InvariantCulture,out n) && double.IsFinite(n);
    private void RefreshAll()
    {
        _updating=true;
        NameBox.Text=_document.Name; WidthBox.Text=F(_document.WidthMm); HeightBox.Text=F(_document.HeightMm);
        ObjectList.ItemsSource=null; ObjectList.ItemsSource=_document.Items;
        ObjectList.SelectedItem=_selected;
        RowInfo.Text=_recordIndex<0 ? $"{_records.Count} rows loaded" : $"Row {_recordIndex+1}/{_records.Count}";
        _updating=false;
        RefreshSelected(); Render();
    }
    private void RefreshSelected()
    {
        _updating=true;
        PropertyPanel.IsEnabled=_selected is not null;
        if(ObjectFormatTab is not null) ObjectFormatTab.IsEnabled=_selected is not null;
        ItemValue.Text=_selected?.Value ?? ""; ItemField.Text=_selected?.DataField ?? "";
        ItemX.Text=_selected is null ? "" : F(_selected.Xmm);
        ItemY.Text=_selected is null ? "" : F(_selected.Ymm);
        ItemWidth.Text=_selected is null ? "" : F(_selected.WidthMm);
        ItemHeight.Text=_selected is null ? "" : F(_selected.HeightMm);
        ItemFontSize.Text=_selected is null ? "" : F(_selected.FontSizePt);
        ItemBold.IsChecked=_selected?.Bold ?? false;
        ItemRotation.Text=_selected is null ? "" : F(_selected.RotationDeg);
        ItemStroke.Text=_selected is null ? "" : F(_selected.StrokeMm);
        _updating=false;
    }
    private void Render()
    {
        EditorCanvas.Width=_document.WidthMm*LabelVisualFactory.DipPerMm;
        EditorCanvas.Height=_document.HeightMm*LabelVisualFactory.DipPerMm;
        EditorCanvas.LayoutTransform=new ScaleTransform(_zoom,_zoom);
        EditorCanvas.Background=GridCheck?.IsChecked==true ? CreateGridBrush() : Brushes.White;
        EditorCanvas.Children.Clear(); _visuals.Clear();
        foreach(var item in _document.Items)
        {
            var element=LabelVisualFactory.CreateItem(item, _recordIndex>=0 ? _records[_recordIndex] : null);
            element.Tag=item.Id;
            if(item==_selected)
            {
                var selectedBorder=new Border { BorderBrush=Brushes.DodgerBlue, BorderThickness=new Thickness(1), Width=item.WidthMm*LabelVisualFactory.DipPerMm,Height=item.HeightMm*LabelVisualFactory.DipPerMm, Child=element };
                selectedBorder.Tag=item.Id;
                element=selectedBorder;
            }
            element.MouseLeftButtonDown += Object_MouseDown;
            element.MouseMove += Object_MouseMove;
            element.MouseLeftButtonUp += Object_MouseUp;
            Canvas.SetLeft(element,item.Xmm*LabelVisualFactory.DipPerMm);
            Canvas.SetTop(element,item.Ymm*LabelVisualFactory.DipPerMm);
            EditorCanvas.Children.Add(element); _visuals[item.Id]=element;
        }
        // The resize grip is editor-only: it is never serialized or printed.
        if (_selected is not null)
        {
            _resizeThumb = new Thumb
            {
                Width = 9, Height = 9,
                Background = Brushes.DodgerBlue,
                BorderBrush = Brushes.White, BorderThickness = new Thickness(1),
                Cursor = Cursors.SizeNWSE,
                ToolTip = "Изменить ширину и высоту объекта"
            };
            _resizeThumb.DragStarted += Resize_DragStarted;
            _resizeThumb.DragDelta += Resize_DragDelta;
            _resizeThumb.DragCompleted += Resize_DragCompleted;
            PositionResizeThumb();
            Panel.SetZIndex(_resizeThumb, 1000);
            EditorCanvas.Children.Add(_resizeThumb);
        }
        else _resizeThumb = null;
    }
    private void PositionResizeThumb()
    {
        if (_selected is null || _resizeThumb is null) return;
        var scale = LabelVisualFactory.DipPerMm;
        Canvas.SetLeft(_resizeThumb, (_selected.Xmm + _selected.WidthMm) * scale - 4.5);
        Canvas.SetTop(_resizeThumb, (_selected.Ymm + _selected.HeightMm) * scale - 4.5);
    }
    private void Resize_DragStarted(object sender, DragStartedEventArgs e)
    {
        if (_selected is null) return;
        _resizeStartW = _selected.WidthMm;
        _resizeStartH = _selected.HeightMm;
        _dragStart = null;
    }
    private void Resize_DragDelta(object sender, DragDeltaEventArgs e)
    {
        if (_selected is null) return;
        var d = LabelVisualFactory.DipPerMm;
        double maxW = Math.Max(0.5, _document.WidthMm - _selected.Xmm);
        double maxH = Math.Max(0.5, _document.HeightMm - _selected.Ymm);
        double w = Math.Clamp(_selected.WidthMm + e.HorizontalChange / d, 0.5, maxW);
        double h = Math.Clamp(_selected.HeightMm + e.VerticalChange / d, 0.5, maxH);
        if (SnapCheck.IsChecked == true) { w = Math.Clamp(Math.Round(w), 0.5, maxW); h = Math.Clamp(Math.Round(h), 0.5, maxH); }
        _selected.WidthMm = w;
        _selected.HeightMm = h;
        if (_visuals.TryGetValue(_selected.Id, out var itemVisual))
        {
            itemVisual.Width = w*d;
            itemVisual.Height = h*d;
        }
        PositionResizeThumb();
        _updating = true;
        ItemWidth.Text = F(w); ItemHeight.Text = F(h);
        _updating = false;
    }
    private void Resize_DragCompleted(object sender, DragCompletedEventArgs e)
    {
        Render();
        StatusText.Text = _selected is null ? "Готово" : $"Размер объекта: {F(_selected.WidthMm)} × {F(_selected.HeightMm)} мм";
    }
    private void Canvas_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (!ReferenceEquals(e.OriginalSource, EditorCanvas)) return;
        _selected = null; ObjectList.SelectedItem = null; RefreshSelected(); Render();
    }
    private void AlignItem(double? x, double? y)
    {
        if (_selected is null) return;
        if (x.HasValue) _selected.Xmm = Math.Max(0, x.Value);
        if (y.HasValue) _selected.Ymm = Math.Max(0, y.Value);
        RefreshSelected(); Render();
    }
    private void AlignLeft_Click(object sender, RoutedEventArgs e) => AlignItem(0, null);
    private void AlignCenter_Click(object sender, RoutedEventArgs e) { if (_selected is not null) AlignItem((_document.WidthMm - _selected.WidthMm) / 2, null); }
    private void AlignRight_Click(object sender, RoutedEventArgs e) { if (_selected is not null) AlignItem(_document.WidthMm - _selected.WidthMm, null); }
    private void AlignTop_Click(object sender, RoutedEventArgs e) => AlignItem(null, 0);
    private void AlignMiddle_Click(object sender, RoutedEventArgs e) { if (_selected is not null) AlignItem(null, (_document.HeightMm - _selected.HeightMm) / 2); }
    private void AlignBottom_Click(object sender, RoutedEventArgs e) { if (_selected is not null) AlignItem(null, _document.HeightMm - _selected.HeightMm); }
    private void Object_MouseDown(object sender,MouseButtonEventArgs e)
    {
        if(sender is not FrameworkElement f || f.Tag is not Guid id) return;
        _selected=_document.Items.FirstOrDefault(x=>x.Id==id);
        if(_selected is null)return;
        ObjectList.SelectedItem=_selected; RefreshSelected(); Render();
        if(_visuals.TryGetValue(id,out var newVisual))
        {
            _dragStart=e.GetPosition(EditorCanvas); _startX=_selected.Xmm; _startY=_selected.Ymm;
            newVisual.CaptureMouse();
        }
        e.Handled=true;
    }
    private void Object_MouseMove(object sender, MouseEventArgs e)
    {
        if (_dragStart is null || _selected is null || e.LeftButton!=MouseButtonState.Pressed)return;
        if(sender is not FrameworkElement f || !_visuals.TryGetValue(_selected.Id,out var current) || !ReferenceEquals(f,current))return;
        var p=e.GetPosition(EditorCanvas);
        var nextX=Math.Clamp(_startX+(p.X-_dragStart.Value.X)/LabelVisualFactory.DipPerMm,0,Math.Max(0,_document.WidthMm-_selected.WidthMm));
        var nextY=Math.Clamp(_startY+(p.Y-_dragStart.Value.Y)/LabelVisualFactory.DipPerMm,0,Math.Max(0,_document.HeightMm-_selected.HeightMm));
        _selected.Xmm=SnapCheck.IsChecked==true ? Math.Round(nextX,MidpointRounding.AwayFromZero) : nextX;
        _selected.Ymm=SnapCheck.IsChecked==true ? Math.Round(nextY,MidpointRounding.AwayFromZero) : nextY;
        Canvas.SetLeft(f,_selected.Xmm*LabelVisualFactory.DipPerMm);
        Canvas.SetTop(f,_selected.Ymm*LabelVisualFactory.DipPerMm);
        PositionResizeThumb();
        _updating=true; ItemX.Text=F(_selected.Xmm); ItemY.Text=F(_selected.Ymm); _updating=false;
    }
    private void Object_MouseUp(object sender,MouseButtonEventArgs e)
    {
        if(_dragStart is not null && sender is FrameworkElement f)f.ReleaseMouseCapture();
        _dragStart=null;
    }
    private void ObjectList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if(_updating)return;
        _selected=ObjectList.SelectedItem as LabelItem;
        RefreshSelected(); Render();
    }
    private void Property_Changed(object sender,RoutedEventArgs e)
    {
        if(_updating || _selected is null)return;
        _selected.Value=ItemValue.Text;_selected.DataField=string.IsNullOrWhiteSpace(ItemField.Text)?null:ItemField.Text.Trim();
        if(TryNum(ItemX.Text,out var x))_selected.Xmm=Math.Clamp(x,0,1000);
        if(TryNum(ItemY.Text,out var y))_selected.Ymm=Math.Clamp(y,0,1000);
        if(TryNum(ItemWidth.Text,out var w) && w>0)_selected.WidthMm=Math.Min(w,1000);
        if(TryNum(ItemHeight.Text,out var h) && h>0)_selected.HeightMm=Math.Min(h,1000);
        if(TryNum(ItemFontSize.Text,out var font) && font>0)_selected.FontSizePt=Math.Min(font,500);
        _selected.Bold=ItemBold.IsChecked==true;
        if(TryNum(ItemRotation.Text,out var rotate)) _selected.RotationDeg=Math.Clamp(rotate,-360,360);
        if(TryNum(ItemStroke.Text,out var stroke) && stroke>0) _selected.StrokeMm=Math.Clamp(stroke,0.1,20);
        Render();
    }
    private void DocumentSettings_LostFocus(object sender,RoutedEventArgs e)
    {
        if(_updating)return;
        _document.Name=NameBox.Text;
        if(TryNum(WidthBox.Text,out var w)&&w>0&&w<=1000)_document.WidthMm=w;
        if(TryNum(HeightBox.Text,out var h)&&h>0&&h<=1000)_document.HeightMm=h;
        RefreshAll();
    }
    private void New_Click(object sender,RoutedEventArgs e)
    {
        _document=new LabelDocument();_selected=null;_path=null;_records.Clear();_recordIndex=-1;RefreshAll();
    }
    private void AddText_Click(object sender,RoutedEventArgs e)
    {
        var item=new LabelItem { Value="New text" };_document.Items.Add(item);_selected=item;RefreshAll();
    }
    private void AddQr_Click(object sender, RoutedEventArgs e)
    {
        var item = new LabelItem { Kind="QR", Value="SEI-2026", Xmm=33,Ymm=4,WidthMm=17,HeightMm=17 };
        _document.Items.Add(item); _selected=item; RefreshAll();
    }
    private void AddCode128_Click(object sender, RoutedEventArgs e)
    {
        var item = new LabelItem { Kind="Code128",Value="SEI-2026",Xmm=5,Ymm=19,WidthMm=45,HeightMm=8 };
        _document.Items.Add(item); _selected=item; RefreshAll();
    }
    private void AddImage_Click(object sender, RoutedEventArgs e)
    {
        var picker=new OpenFileDialog { Title="Выбрать изображение",Filter="Изображения|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Все файлы|*.*" };
        if(picker.ShowDialog(this)!=true)return;
        try
        {
            var file=new System.IO.FileInfo(picker.FileName);
            if(file.Length>10*1024*1024) { MessageBox.Show(this,"Размер изображения должен быть не более 10 МБ.");return; }
            var item=new LabelItem { Kind="Image",Value=file.Name,Xmm=10,Ymm=7,WidthMm=20,HeightMm=15,
                ImageDataBase64=Convert.ToBase64String(System.IO.File.ReadAllBytes(picker.FileName)) };
            _document.Items.Add(item);_selected=item;RefreshAll();
        }
        catch(Exception ex) { ShowError(ex); }
    }
    private void AddBox_Click(object sender,RoutedEventArgs e)
    {
        var item=new LabelItem { Kind="Box",Value="Rectangle",WidthMm=15,HeightMm=10 };_document.Items.Add(item);_selected=item;RefreshAll();
    }

    private static Brush CreateGridBrush()
    {
        var mm=LabelVisualFactory.DipPerMm;
        var geometry=new GeometryGroup();
        geometry.Children.Add(new LineGeometry(new Point(0,0),new Point(mm,0)));
        geometry.Children.Add(new LineGeometry(new Point(0,0),new Point(0,mm)));
        var drawing=new GeometryDrawing(null,new Pen(new SolidColorBrush(Color.FromRgb(232,236,241)),0.4),geometry);
        var brush=new DrawingBrush(drawing) { TileMode=TileMode.Tile, Viewport=new Rect(0,0,mm,mm),ViewportUnits=BrushMappingMode.Absolute,Stretch=Stretch.None };
        brush.Freeze();return brush;
    }
    private void GridChanged_Click(object sender,RoutedEventArgs e)=>Render();
    private void Zoom_Changed(object sender,SelectionChangedEventArgs e)
    {
        if(EditorCanvas is null || ZoomBox.SelectedItem is not ComboBoxItem option) return;
        var label=option.Content?.ToString()?.TrimEnd('%');
        if(double.TryParse(label,NumberStyles.Float,CultureInfo.InvariantCulture,out var percent))
            _zoom=percent/100.0;
        Render();
    }
    private void AddEllipse_Click(object sender,RoutedEventArgs e)
    {
        var item=new LabelItem { Kind="Ellipse",Value="Ellipse",WidthMm=15,HeightMm=10 };
        _document.Items.Add(item);_selected=item;RefreshAll();
    }
    private void AddLine_Click(object sender,RoutedEventArgs e)
    {
        var item=new LabelItem { Kind="Line",Value="Line",WidthMm=20,HeightMm=3 };
        _document.Items.Add(item);_selected=item;RefreshAll();
    }
    private void Duplicate_Click(object sender,RoutedEventArgs e)
    {
        if(_selected is null)return;
        var copy=new LabelItem
        {
            Kind=_selected.Kind,Value=_selected.Value,DataField=_selected.DataField,
            ImageDataBase64=_selected.ImageDataBase64,
            Xmm=Math.Min(_document.WidthMm-1,_selected.Xmm+2),
            Ymm=Math.Min(_document.HeightMm-1,_selected.Ymm+2),
            WidthMm=_selected.WidthMm,HeightMm=_selected.HeightMm,FontSizePt=_selected.FontSizePt,
            Bold=_selected.Bold,RotationDeg=_selected.RotationDeg,StrokeMm=_selected.StrokeMm
        };
        _document.Items.Add(copy);_selected=copy;RefreshAll();
    }
    private void Front_Click(object sender,RoutedEventArgs e)
    {
        if(_selected is null)return;
        _document.Items.Remove(_selected);_document.Items.Add(_selected);RefreshAll();
    }
    private void Back_Click(object sender,RoutedEventArgs e)
    {
        if(_selected is null)return;
        _document.Items.Remove(_selected);_document.Items.Insert(0,_selected);RefreshAll();
    }
    private void Window_PreviewKeyDown(object sender,KeyEventArgs e)
    {
        if(e.OriginalSource is TextBox || e.OriginalSource is ComboBox || e.OriginalSource is CheckBox)return;
        if(e.Key==Key.S && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { Save_Click(sender,e);e.Handled=true;return; }
        if(e.Key==Key.O && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { Open_Click(sender,e);e.Handled=true;return; }
        if(e.Key==Key.D && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { Duplicate_Click(sender,e);e.Handled=true;return; }
        if(e.Key==Key.Delete) { Delete_Click(sender,e);e.Handled=true;return; }
        if(_selected is null)return;
        var step=Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)?1:0.25;
        double dx=0,dy=0;
        switch(e.Key){ case Key.Left:dx=-step;break;case Key.Right:dx=step;break;case Key.Up:dy=-step;break;case Key.Down:dy=step;break;default:return; }
        _selected.Xmm=Math.Clamp(_selected.Xmm+dx,0,Math.Max(0,_document.WidthMm-_selected.WidthMm));
        _selected.Ymm=Math.Clamp(_selected.Ymm+dy,0,Math.Max(0,_document.HeightMm-_selected.HeightMm));
        RefreshSelected();Render();e.Handled=true;
    }

    private void Delete_Click(object sender,RoutedEventArgs e)
    {
        if(_selected is null)return;
        _document.Items.Remove(_selected);_selected=null;RefreshAll();
    }
    private void Save_Click(object sender,RoutedEventArgs e)
    {
        try
        {
            var dialog=new SaveFileDialog { Filter="Label Studio JSON (*.label.json)|*.label.json|JSON (*.json)|*.json",FileName=_path is null ? "label.label.json" : System.IO.Path.GetFileName(_path) };
            if(dialog.ShowDialog()!=true)return;
            DocumentStore.Save(dialog.FileName,_document);_path=dialog.FileName;StatusText.Text=$"Saved {dialog.FileName}";
        }
        catch(Exception ex){ ShowError(ex); }
    }
    private void Open_Click(object sender,RoutedEventArgs e)
    {
        try
        {
            var dialog=new OpenFileDialog { Filter="Label Studio JSON (*.json)|*.json" };
            if(dialog.ShowDialog()!=true)return;
            _document=DocumentStore.Load(dialog.FileName);_selected=null;_path=dialog.FileName;_recordIndex=-1;RefreshAll();StatusText.Text=$"Opened {dialog.FileName}";
        }
        catch(Exception ex){ ShowError(ex); }
    }
    private void LoadCsv_Click(object sender,RoutedEventArgs e)
    {
        try
        {
            var dialog=new OpenFileDialog { Filter="CSV (*.csv;*.txt)|*.csv;*.txt" };
            if(dialog.ShowDialog()!=true)return;
            _records=CsvDataSource.Read(dialog.FileName);_recordIndex=_records.Count>0?0:-1;
            RefreshAll();StatusText.Text=$"CSV: {_records.Count} rows. Use CSV column in object properties for dynamic text.";
        }
        catch(Exception ex){ ShowError(ex); }
    }
    private void Previous_Click(object sender,RoutedEventArgs e) { if(_recordIndex>0)_recordIndex--;RefreshAll(); }
    private void Next_Click(object sender,RoutedEventArgs e) { if(_recordIndex+1<_records.Count)_recordIndex++;RefreshAll(); }
    private void ClearPreview_Click(object sender,RoutedEventArgs e) { _recordIndex=-1;RefreshAll(); }
    private void Print_Click(object sender,RoutedEventArgs e)
    {
        if(MessageBox.Show(this,"This uses the installed Windows printer driver. Verify paper size and printer settings before printing. THM RAW, ZPL, TSPL, JScript, EZPL are NOT active in this build. Continue?","Print confirmation",MessageBoxButton.YesNo,MessageBoxImage.Warning)!=MessageBoxResult.Yes)return;
        try { var record=_recordIndex>=0?_records[_recordIndex]:null; if(WindowsVisualPrinter.Print(_document,record))StatusText.Text="Задание передано драйверу Windows (физическая печать не подтверждена)."; }
        catch(Exception ex){ ShowError(ex); }
    }
    private void ShowError(Exception ex)=>MessageBox.Show(this,ex.Message,"Error",MessageBoxButton.OK,MessageBoxImage.Error);
}
