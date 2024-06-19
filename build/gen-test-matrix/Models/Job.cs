namespace GenTestMatrix.Models;

internal record Job
{
    public required string Title { get; init; }
    public required OS OS { get; init; }
    public required Dotnet Dotnet { get; init; }
    public required string Arch { get; init; }
    public bool? UsePGO { get; init; }
}
