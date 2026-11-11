module Main where
import Control.Monad (replicateM, unless)
import Data.List (sort)
import Golem.Layout.Paginate
import Golem.Layout.Code
import Golem.Layout.RuleArea
import Golem.Syntax
data Piece = Rule | Code | Columns | Restore | NeedRows | Blank | Adjust | KeepTogether | Table | Wrapped deriving (Eq, Show, Enum, Bounded)
flow :: Int -> Piece -> (Flow,[Int])
flow i x = let n = i*10; l = LineBox n [] [] [] 0; at = mkSpan (FileId 0) i (i+1) in case x of
  Rule -> (FRuled n (Just (RuleSide 0 0 1 False Nothing)) Nothing False (RuleGrid 10 8) 0 (RuledLines defaultKeep [l]), [n])
  Code -> (FCode (codeGeometry 8 10 8 0) 0 1 False [l], [n])
  Columns -> (FSwitchColumns (ColumnSet 2 0 0 0),[])
  Restore -> (FRestoreColumns,[])
  NeedRows -> (FNeedLines at 2,[])
  Blank -> (FBlank at 1,[])
  Adjust -> (FAdjustLines at (-1),[])
  KeepTogether -> (FNoBreak at,[])
  Table -> (FTable n 0 [] [[l]] [] False,[n])
  Wrapped -> (FWrapped (1000+n) 1 [] [] [l],[n])
main :: IO ()
main = do
  let cases = [(cap,xs) | cap <- [3..5], n <- [0..3], xs <- replicateM n [minBound..maxBound]]
      check (cap,xs) =
        let entries = zipWith flow [1..] xs
            ps = paginate 1 cap (map fst entries)
            slots = concatMap poSlots ps
            ids (SLine i) = [i]
            ids (SCode start count _) = [start..start+count-1]
            ids _ = []
        in sort (concatMap (ids . snd) slots) == sort (concatMap snd entries) &&
           all (\p -> all (\(r,_) -> r >= 0 && r < poLines p) (poSlots p)) ps &&
           sort [i | (_,SWrapped i) <- slots] == [1000+i*10 | (i,Wrapped) <- zip [1..] xs]
  case filter (not . check) cases of
    [] -> putStrLn ("P1/P2 flows=" ++ show (length cases))
    bad:_ -> fail (show bad)
