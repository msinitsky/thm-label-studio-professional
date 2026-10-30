using System.IO;
using System.Text;
namespace LabelStudio.App.Services;
public static class CsvDataSource
{
    // Supports quoted, delimiter-separated CSV; BOM; semicolon/comma/tab.
    public static List<Dictionary<string,string>> Read(string path)
    {
        var content = File.ReadAllText(path, Encoding.UTF8);
        var firstLine = content.Split('\n', 2)[0];
        var separator = new[] { ';', ',', '\t' }.OrderByDescending(c => firstLine.Count(x => x == c)).First();
        var rows = Parse(content, separator);
        if (rows.Count == 0) return new();
        var headers = rows[0].Select(x => x.Trim().TrimStart('\uFEFF')).ToArray();
        var records = new List<Dictionary<string,string>>();
        foreach (var row in rows.Skip(1))
        {
            if (row.All(string.IsNullOrWhiteSpace)) continue;
            var record = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            for (int i=0; i<headers.Length; i++)
                if (!string.IsNullOrWhiteSpace(headers[i])) record[headers[i]] = i < row.Count ? row[i] : "";
            records.Add(record);
        }
        return records;
    }
    private static List<List<string>> Parse(string text, char separator)
    {
        var rows = new List<List<string>>(); var row = new List<string>(); var cell = new StringBuilder(); bool quoted=false;
        for (int i=0;i<text.Length;i++)
        {
            var c=text[i];
            if (c=='\"')
            {
                if (quoted && i+1<text.Length && text[i+1]=='\"') { cell.Append('\"'); i++; }
                else quoted=!quoted;
            }
            else if (!quoted && c==separator) { row.Add(cell.ToString()); cell.Clear(); }
            else if (!quoted && (c=='\r' || c=='\n'))
            {
                if (c=='\r' && i+1<text.Length && text[i+1]=='\n') i++;
                row.Add(cell.ToString()); cell.Clear();
                rows.Add(row); row=new();
            }
            else cell.Append(c);
        }
        if (quoted) throw new InvalidDataException("CSV has an unclosed quoted field");
        if (cell.Length>0 || row.Count>0) { row.Add(cell.ToString()); rows.Add(row); }
        return rows;
    }
}
