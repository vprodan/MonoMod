using System;
using Xunit;
using Xunit.Abstractions;

namespace MonoMod.UnitTest
{
    public class Temp : TestBase
    {
        public Temp(ITestOutputHelper helper) : base(helper) { }

        [Fact]
        public void MyThing()
        {
            Assert.Equal("abc", "abc".AsSpan().ToArray());
        }
    }
}