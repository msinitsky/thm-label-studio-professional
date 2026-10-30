using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using LabelStudio.App.Models;
using LabelStudio.App.Services;
namespace LabelStudio.App.Printing;
public static class WindowsVisualPrinter
{
    public static bool Print(LabelDocument doc, IReadOnlyDictionary<string,string>? record=null)
    {
        var dialog=new PrintDialog();
        if (dialog.ShowDialog() != true) return false;
        // Page media and sensor settings remain driver-controlled. This path is not THM RAW.
        var visual=LabelVisualFactory.CreateCanvas(doc,record);
        var size=new Size(visual.Width,visual.Height);
        visual.Measure(size); visual.Arrange(new Rect(size)); visual.UpdateLayout();
        dialog.PrintVisual(visual,$"LabelStudio: {doc.Name}");
        return true;
    }
}
