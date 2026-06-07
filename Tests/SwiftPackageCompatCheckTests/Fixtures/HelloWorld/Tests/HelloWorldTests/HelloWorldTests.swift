import Testing
@testable import HelloWorld

@Test
func greetReturnsHelloWorld() {
    #expect(HelloWorld.greet() == "Hello, world!")
}

@Test
func greetIsStable() {
    // The greeting is deterministic — calling twice should return the same value.
    #expect(HelloWorld.greet() == HelloWorld.greet())
}
