using LabelStudio.App.Models;
namespace LabelStudio.App.Printing;
public interface IPrinterAdapter
{
    string Id { get; }
    string DisplayName { get; }
    bool CanPrint { get; }
    void Print(LabelDocument document, IReadOnlyDictionary<string,string>? fields);
}
