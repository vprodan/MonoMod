using MonoMod.Core.Platforms;

namespace ConsoleApp1;

class Program
{
    static void Main(string[] args)
    {
        if (PlatformTriple.Current is null)
        {
            throw new Exception();
        }
        
        if (PlatformTriple.Current is null)
        {
            throw new Exception();
        }
        
        Console.WriteLine("Hello");
    }
}