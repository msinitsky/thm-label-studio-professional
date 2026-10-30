using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using LabelStudio.App.Models;
using LabelStudio.App.Services;

namespace LabelStudio.App;

/// <summary>
/// Windows print-queue batch dispatcher. Does NOT claim physical print acknowledgement.
/// The selected Windows driver controls media handling and resolution.
/// </summary>
public sealed class BatchPrintWindow : Window
{
    private readonly LabelDocument _doc;
    private readonly IReadOnlyList<Dictionary<string,string>> _rows;
    private readonly TextBox _start = new() { Text="1", Width=62, Margin=new Thickness(4) };
    private readonly TextBox _end = new() { Width=62, Margin=new Thickness(4) };
    private readonly TextBox _copies = new() { Text="1", Width=62, Margin=new Thickness(4) };
    private readonly TextBlock _status = new() { Margin=new Thickness(9,4), TextWrapping=TextWrapping.Wrap };
    private readonly TextBox _log = new() { IsReadOnly=true, AcceptsReturn=true, VerticalScrollBarVisibility=ScrollBarVisibility.Auto, HorizontalScrollBarVisibility=ScrollBarVisibility.Auto, FontFamily=new FontFamily("Consolas"), FontSize=11 };
    private readonly Image _preview = new() { Stretch=Stretch.Uniform };
    private readonly Button _startButton = new() { Content="Отправить партию", Padding=new Thickness(16,7), Margin=new Thickness(4) };
    private readonly Button _pauseButton = new() { Content="Пауза", Padding=new Thickness(14,7), Margin=new Thickness(4), IsEnabled=false };
    private readonly Button _closeButton = new() { Content="Закрыть", Padding=new Thickness(14,7), Margin=new Thickness(4) };
    private readonly System.Windows.Controls.Slider _slider;
    private bool _running, _paused;
    private int _accepted;
    private readonly string _journalPath;

    public BatchPrintWindow(LabelDocument doc, IReadOnlyList<Dictionary<string,string>> rows)
    {
        _doc=doc;
        _rows=rows;
        Title="Диспетчер печати — Excel / CSV — THM Label Studio Professional";
        Width=1000; Height=740; MinWidth=750; MinHeight=570;
        WindowStartupLocation=WindowStartupLocation.CenterOwner;
        _end.Text=rows.Count.ToString(CultureInfo.InvariantCulture);
        _slider=new System.Windows.Controls.Slider { Minimum=1,Maximum=rows.Count,Value=1,TickFrequency=1,IsSnapToTickEnabled=true,Margin=new Thickness(9) };
        var logDir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"THMLabelStudio","Logs");
        Directory.CreateDirectory(logDir);
        _journalPath=Path.Combine(logDir,$"batch-{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid().ToString("N")[..6]}.log");

        var root=new DockPanel { Margin=new Thickness(12) };
        var bar=new WrapPanel { Margin=new Thickness(0,0,0,7) };
        bar.Children.Add(new TextBlock { Text="С первой строки",VerticalAlignment=VerticalAlignment.Center }); bar.Children.Add(_start);
        bar.Children.Add(new TextBlock { Text="По строку",VerticalAlignment=VerticalAlignment.Center }); bar.Children.Add(_end);
        bar.Children.Add(new TextBlock { Text="Копий каждой",VerticalAlignment=VerticalAlignment.Center }); bar.Children.Add(_copies);
        var viewButton=new Button { Content="Просмотреть",Padding=new Thickness(12,7),Margin=new Thickness(4) };
        viewButton.Click += (_,_)=>UpdatePreview();
        bar.Children.Add(viewButton);
        DockPanel.SetDock(bar,Dock.Top);root.Children.Add(bar);
        var actions=new WrapPanel { Margin=new Thickness(0,5,0,9) };
        _startButton.Click += async (_,_)=>await StartBatchAsync();
        _pauseButton.Click += (_,_)=> { _paused=!_paused; _pauseButton.Content=_paused?"Продолжить":"Пауза"; Append(_paused?"Пауза отправки новых заданий":"Возобновление отправки"); };
        _closeButton.Click += (_,_) => { if(!_running) Close(); else _paused=true; };
        actions.Children.Add(_startButton); actions.Children.Add(_pauseButton); actions.Children.Add(_closeButton);
        DockPanel.SetDock(actions,Dock.Bottom); root.Children.Add(actions);
        DockPanel.SetDock(_status,Dock.Bottom);root.Children.Add(_status);
        var content=new Grid();content.RowDefinitions.Add(new RowDefinition { Height=new GridLength(3,GridUnitType.Star) });content.RowDefinitions.Add(new RowDefinition { Height=new GridLength(2,GridUnitType.Star) });
        var previewPanel=new DockPanel();
        DockPanel.SetDock(_slider,Dock.Bottom);previewPanel.Children.Add(_slider);
        var previewFrame=new Border { Background=Brushes.White,BorderBrush=Brushes.LightGray,BorderThickness=new Thickness(1),Padding=new Thickness(15),Child=_preview };
        previewPanel.Children.Add(previewFrame);
        Grid.SetRow(previewPanel,0);content.Children.Add(previewPanel);
        Grid.SetRow(_log,1);content.Children.Add(_log);
        root.Children.Add(content);Content=root;
        _slider.ValueChanged += (_,_) => UpdatePreview();
        Closing += (_,e)=> { if(_running) { e.Cancel=true;MessageBox.Show(this,"Сначала дождитесь завершения отправки заданий. Можно нажать «Пауза». Не закрывайте программу во время отправки."); } };
        UpdatePreview();
        _status.Text=$"Загружено {_rows.Count} записей. Профиль материала и настройки печати задаются драйвером Windows.";
    }

    private static int ReadInt(TextBox box,string field,int min,int max)
    {
        if(!int.TryParse(box.Text,NumberStyles.Integer,CultureInfo.InvariantCulture,out var n) || n<min || n>max)
            throw new InvalidDataException($"{field}: требуется целое число от {min} до {max}.");
        return n;
    }
    private void Append(string text)
    {
        var line=$"{DateTime.Now:yyyy-MM-dd HH:mm:ss} | {text}";
        _log.AppendText(line+Environment.NewLine);
        _log.ScrollToEnd();
        try { File.AppendAllText(_journalPath,line+Environment.NewLine,Encoding.UTF8); }
        catch (IOException) { _status.Text="Ошибка записи журнала. Проверьте папку Logs."; }
    }
    private void UpdatePreview()
    {
        if(_preview is null || _slider is null) return;
        var index=Math.Clamp((int)_slider.Value-1,0,_rows.Count-1);
        var canvas=LabelVisualFactory.CreateCanvas(_doc,_rows[index]);
        // A VisualBrush displays the same WPF canvas that will be printed.
        canvas.Measure(new Size(canvas.Width,canvas.Height));
        canvas.Arrange(new Rect(0,0,canvas.Width,canvas.Height));
        canvas.UpdateLayout();
        var brush=new VisualBrush(canvas) { Stretch=Stretch.Uniform };
        var drawing=new DrawingVisual();
        using(var dc=drawing.RenderOpen()) dc.DrawRectangle(brush,null,new Rect(0,0,canvas.Width,canvas.Height));
        var bitmap=new System.Windows.Media.Imaging.RenderTargetBitmap(Math.Max(1,(int)Math.Ceiling(canvas.Width)),Math.Max(1,(int)Math.Ceiling(canvas.Height)),96,96,PixelFormats.Pbgra32);
        bitmap.Render(drawing);
        _preview.Source=bitmap;
        _status.Text=$"Просмотр записи {index+1} из {_rows.Count}. Значения из Excel/CSV.";
    }
    private async Task StartBatchAsync()
    {
        if(_running)return;
        int first,last,multiple;
        try
        {
            first=ReadInt(_start,"Первая строка",1,_rows.Count);
            last=ReadInt(_end,"Последняя строка",first,_rows.Count);
            multiple=ReadInt(_copies,"Копии",1,100);
        }
        catch(Exception ex) { MessageBox.Show(this,ex.Message,"Некорректный диапазон");return; }
        var total=checked((last-first+1)*multiple);
        if(total>500) { MessageBox.Show(this,"Ограничение тестовой версии — 500 заданий за партию.");return; }
        var confirm=MessageBox.Show(this,$"Отправить {total} заданий (строки {first}–{last}) через Windows-драйвер?\n\nОТПРАВЛЕНО ≠ ФИЗИЧЕСКИ НАПЕЧАТАНО. Проверьте размеры и носитель.","Подтверждение печати",MessageBoxButton.YesNo,MessageBoxImage.Warning);
        if(confirm!=MessageBoxResult.Yes)return;
        var dialog=new PrintDialog();
        if(dialog.ShowDialog()!=true)return;
        _running=true;_paused=false;_accepted=0;_startButton.IsEnabled=false;_pauseButton.IsEnabled=true;
        _start.IsEnabled=false;_end.IsEnabled=false;_copies.IsEnabled=false;
        Append($"START | jobs={total} | source-rows={first}-{last} | copies={multiple} | printer={dialog.PrintQueue?.FullName}");
        try
        {
            for(int row=first;row<=last;row++)
            for(int copy=1;copy<=multiple;copy++)
            {
                while(_paused) await Task.Delay(100);
                // PrintVisual only confirms submission to the Windows print pipeline.
                var visual=LabelVisualFactory.CreateCanvas(_doc,_rows[row-1]);
                var size=new Size(visual.Width,visual.Height);
                visual.Measure(size);visual.Arrange(new Rect(size));visual.UpdateLayout();
                try { dialog.PrintVisual(visual,$"LabelStudio row={row} copy={copy}"); }
                catch(Exception ex)
                {
                    Append($"FAILED | row={row} | copy={copy} | {ex.Message}");
                    MessageBox.Show(this,"Передача задания завершилась ошибкой. Проверьте очередь и фактическую печать перед повторным запуском, чтобы избежать дубликатов.\n"+ex.Message,"Ошибка печати",MessageBoxButton.OK,MessageBoxImage.Error);
                    return;
                }
                _accepted++;
                Append($"SUBMITTED | row={row} | copy={copy} | {_accepted}/{total} | physical output NOT confirmed");
                _status.Text=$"Передано Windows: {_accepted}/{total}. Физическая печать не подтверждена.";
                await Task.Delay(160); // permit UI to process Pause; not a printer completion signal
            }
            Append("DONE | all jobs submitted to Windows print pipeline");
        }
        finally
        {
            _running=false;_paused=false;_startButton.IsEnabled=true;_pauseButton.IsEnabled=false;_pauseButton.Content="Пауза";
            _start.IsEnabled=true;_end.IsEnabled=true;_copies.IsEnabled=true;
            _status.Text=$"Передано Windows: {_accepted}/{total}. Проверьте фактическую печать и состояние принтера.";
        }
    }
}
