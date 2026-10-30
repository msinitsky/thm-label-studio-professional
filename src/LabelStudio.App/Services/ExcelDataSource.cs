using ClosedXML.Excel;
using System.Globalization;
using System.IO;

namespace LabelStudio.App.Services;

public static class ExcelDataSource
{
    // Read displayed values as text so inventory codes with leading zeros are retained.
    // First row defines unique, non-empty column names. Data begins with row 2.
    public static List<Dictionary<string, string>> Read(string path)
    {
        using var workbook = new XLWorkbook(path);
        var sheet = workbook.Worksheets.FirstOrDefault() ?? throw new InvalidDataException("Excel workbook has no worksheet.");
        var used = sheet.RangeUsed() ?? throw new InvalidDataException("Excel worksheet is empty.");
        if (used.ColumnCount() > 256 || used.RowCount() > 50001)
            throw new InvalidDataException("The source is too large (limit 256 columns / 50000 records).");
        var headerRow = used.FirstRow();
        var headers = headerRow.Cells().Select(c => c.GetFormattedString().Trim().TrimStart('\uFEFF')).ToArray();
        if (headers.Length == 0 || headers.All(string.IsNullOrWhiteSpace))
            throw new InvalidDataException("The first row must contain column names.");
        var unique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var h in headers)
            if (!string.IsNullOrWhiteSpace(h) && !unique.Add(h))
                throw new InvalidDataException($"Duplicate column name: {h}");
        var records = new List<Dictionary<string,string>>();
        foreach (var row in used.Rows().Skip(1))
        {
            var record = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            var any = false;
            for (int i=0; i<headers.Length; i++)
            {
                if (string.IsNullOrWhiteSpace(headers[i])) continue;
                var cell = row.Cell(i+1);
                var value = cell.GetFormattedString(CultureInfo.CurrentCulture);
                record[headers[i]] = value;
                any |= !string.IsNullOrWhiteSpace(value);
            }
            if (any) records.Add(record);
        }
        return records;
    }
}
