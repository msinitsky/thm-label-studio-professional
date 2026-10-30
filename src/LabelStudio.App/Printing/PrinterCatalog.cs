namespace LabelStudio.App.Printing;
public sealed record PrinterCapability(string Id, string Name, string Language, string Status);
public static class PrinterCatalog
{
    public static readonly PrinterCapability[] Planned =
    [
        new("windows", "Windows printer", "WPF/GDI", "Basic output implemented"),
        new("zebra", "Zebra", "ZPL", "Adapter not implemented"),
        new("tsc", "TSC", "TSPL", "Adapter not implemented"),
        new("cab", "CAB", "JScript", "Adapter not implemented"),
        new("godex", "Godex", "EZPL", "Adapter not implemented"),
        new("thm", "Weidmüller THM MultiMark", "Captured RAW", "v0.11 reference; C# port not implemented")
    ];
}
