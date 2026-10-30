using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
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
        ItemValue.Text=_selected?.Value ?? ""; ItemField.Text=_selected?.DataField ?? "";
        ItemX.Text=_selected is null ? "" : F(_selected.Xmm);
        ItemY.Text=_selected is null ? "" : F(_selected.Ymm);
        ItemWidth.Text=_selected is null ? "" : F(_selected.WidthMm);
        ItemHeight.Text=_selected is null ? "" : F(_selected.HeightMm);
        ItemFontSize.Text=_selected is null ? "" : F(_selected.FontSizePt);
        ItemBold.IsChecked=_selected?.Bold ?? false;
        _updating=false;
    }
    private void Render()
    {
        EditorCanvas.Width=_document.WidthMm*LabelVisualFactory.DipPerMm;
        EditorCanvas.Height=_document.HeightMm*LabelVisualFactory.DipPerMm;
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
    }
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
        _selected.Xmm=Math.Clamp(_startX+(p.X-_dragStart.Value.X)/LabelVisualFactory.DipPerMm,0,Math.Max(0,_document.WidthMm-_selected.WidthMm));
        _selected.Ymm=Math.Clamp(_startY+(p.Y-_dragStart.Value.Y)/LabelVisualFactory.DipPerMm,0,Math.Max(0,_document.HeightMm-_selected.HeightMm));
        Canvas.SetLeft(f,_selected.Xmm*LabelVisualFactory.DipPerMm);
        Canvas.SetTop(f,_selected.Ymm*LabelVisualFactory.DipPerMm);
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
    private void AddBox_Click(object sender,RoutedEventArgs e)
    {
        var item=new LabelItem { Kind="Box",Value="Rectangle",WidthMm=15,HeightMm=10 };_document.Items.Add(item);_selected=item;RefreshAll();
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
        try { var record=_recordIndex>=0?_records[_recordIndex]:null; if(WindowsVisualPrinter.Print(_document,record))StatusText.Text="Print job submitted through Windows driver (physical completion not confirmed)."; }
        catch(Exception ex){ ShowError(ex); }
    }
    private void ShowError(Exception ex)=>MessageBox.Show(this,ex.Message,"Error",MessageBoxButton.OK,MessageBoxImage.Error);
}
