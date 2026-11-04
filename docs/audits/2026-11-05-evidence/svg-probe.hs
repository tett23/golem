{-# LANGUAGE OverloadedStrings #-}
import Golem.Svg.Active
main = mapM_ (\(n,s) -> putStrLn (n ++ ": " ++ show (activeContent s)))
  [ ("script-control", "<svg xmlns=\"http://www.w3.org/2000/svg\"><script>void(0)</script></svg>")
  , ("href-control", "<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"https://example.invalid/a\"/></svg>")
  , ("presentation-url", "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect fill=\"url(https://example.invalid/a#g)\"/></svg>")
  , ("stylesheet-pi", "<?xml-stylesheet type=\"text/css\" href=\"https://example.invalid/a.css\"?><svg xmlns=\"http://www.w3.org/2000/svg\"/>")
  , ("animated-style", "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect><set attributeName=\"style\" to=\"fill:url(https://example.invalid/a#g)\"/></rect></svg>")
  ]
