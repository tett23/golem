module Main where
import Control.Monad (unless)
import Data.Ratio
import Golem.Length
import Golem.Layout.Paginate
main :: IO ()
main = do
  let half n = let (q,r) = n `divMod` 2 in q + if r == 1 && odd q then 1 else 0
      units = [Pt,Mm,In,Q,H]
      cases = [(n,u) | n <- [-32..32], u <- units]
      scale u = case u of Pt -> 65536; In -> 4718592; Mm -> 23592960 % 127; Q -> 5898240 % 127; H -> 5898240 % 127
      lengthOK (n,u) = toSp u (n % 2 / scale u) == Sp (half n)
      headings = [(f,p,s,m,k) | f <- [1..4], p <- [f..6], s <- [1..8], m <- [1..3], k <- [1..3]]
      headingOK (f,p,s,m,k) =
        let HeadingBlock (Sp pitch) n (Sp off) = headingBlock (Sp f) (Sp p) (Sp s) m k
            distance = abs (pitch*f - p*s)
            extent = fromIntegral (m-1)*pitch+s
            area t = fromIntegral (t-1)*p+f
        in 2*distance <= f && (2*distance /= f || even pitch) &&
           n >= k && area n >= extent && (n == k || area (n-1) < extent) && (area n - extent - 2*off) `elem` [0,1]
  unless (all lengthOK cases && all headingOK headings) $ fail "rounding counterexample"
  putStrLn ("L1 half-units=" ++ show (length cases) ++ " L2/L3 headings=" ++ show (length headings))
