import Lexical
import LexicalLinkPlugin
import LexicalListPlugin

public enum Haklex {
  public static func plugins() -> [Plugin] {
    [ListPlugin(), LinkPlugin()]
  }
}
