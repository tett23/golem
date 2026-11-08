{- | The colours a PDF paints with, its fonts not embedded and its spot
colorants (docs/adr ADR 0232), on hand-made objects.
-}
module PaintSpec (tests) where

import Codec.Compression.Zlib qualified as Z
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Golem.Pdf
import Test.Tasty
import Test.Tasty.HUnit

flated :: ByteString -> Obj
flated b = OStream [("Filter", OName "FlateDecode")] (BL.toStrict (Z.compress (BL.fromStrict b)))

{- | A PDF of pages, each a content stream and its resources: object 1 the
catalog, 2 the page tree, then each page followed by its content, then the
extra objects from 'extraBase'.
-}
pdfOf :: [(ByteString, [(Text, Obj)])] -> [Obj] -> PdfObjects
pdfOf pages extra =
  PdfObjects "1.6" objs (ODict [("Root", ORef 1)])
  where
    n = length pages
    pageObj i = 3 + 2 * i
    objs =
      [ ODict [("Type", OName "Catalog"), ("Pages", ORef 2)],
        ODict [("Type", OName "Pages"), ("Kids", OArr [ORef (pageObj i) | i <- [0 .. n - 1]]), ("Count", OInt (fromIntegral n))]
      ]
        <> concat
          [ [ ODict [("Type", OName "Page"), ("Parent", ORef 2), ("Resources", ODict res), ("Contents", ORef (pageObj i + 1))],
              flated content
            ]
          | (i, (content, res)) <- zip [0 ..] pages
          ]
        <> extra

-- | The number of the first extra object of a PDF of n pages.
extraBase :: Int -> Int
extraBase n = 3 + 2 * n

onePage :: ByteString -> [(Text, Obj)] -> [Obj] -> PdfObjects
onePage content res = pdfOf [(content, res)]

reg :: (Text, Obj)
reg = ("ColorSpace", ODict [("Reg", OArr [OName "Separation", OName "All", OName "DeviceCMYK", ORef 99])])

page' :: PaintSpace -> [Text] -> Text -> Paint
page' sp cs op = Paint 1 op PageContent sp cs

summary :: PdfObjects -> [(Int, Text, PaintSource, PaintSpace, [Text])]
summary objs = [(paPage p, paOperator p, paSource p, paSpace p, paComponents p) | p <- paintsOf objs]

descriptor :: [(Text, Obj)] -> Obj
descriptor extra = ODict ([("Type", OName "FontDescriptor"), ("FontName", OName "ABCDEF+Body")] <> extra)

tests :: TestTree
tests =
  testGroup
    "paints, fonts not embedded and spot colorants (docs/adr ADR 0232)"
    [ testCase "I7: q 0 0 0 1 k re f Q, then the registration colour" $
        paintsOf (onePage "q 0 0 0 1 k 0 0 1 1 re f Q /Reg cs 1 scn 0 0 1 1 re f" [reg] [])
          @?= [page' PsDeviceCmyk ["0", "0", "0", "1"] "f", page' (PsSeparation "All") ["1"] "f"],
      testCase "I7: the colour set inside q is gone after Q" $
        map paSpace (paintsOf (onePage "q 0 0 1 0 k Q 0 0 1 1 re f" [] [])) @?= [PsDeviceGray],
      testCase "I7: after Q the initial colour, DeviceGray 0" $
        paintsOf (onePage "q 0 0 1 0 k Q 0 0 1 1 re f" [] []) @?= [page' PsDeviceGray ["0"] "f"],
      testCase "I7: nested q and Q restore each level" $
        map paComponents (paintsOf (onePage "0.5 g q 0.2 g q 0.1 g Q 0 0 1 1 re f Q 0 0 1 1 re f" [] [])) @?= [["0.2"], ["0.5"]],
      testCase "an empty content stream paints nothing" $
        paintsOf (onePage "" [] []) @?= [],
      testCase "the device colour operators, fill and stroke apart" $
        summary (onePage "1 0 0 rg 0 0 1 RG 0 0 0 1 k 0.5 G 0 0 1 1 re f 0 0 m 1 1 l S" [] [])
          @?= [(1, "f", PageContent, PsDeviceCmyk, ["0", "0", "0", "1"]), (1, "S", PageContent, PsDeviceGray, ["0.5"])],
      testCase "B, B*, b and b* fill and stroke: two paints each" $
        map (\p -> (paOperator p, paSpace p)) (paintsOf (onePage "1 0 0 rg 0 0 0 1 K 0 0 1 1 re B 0 0 1 1 re b*" [] []))
          @?= [("B", PsDeviceRgb), ("B", PsDeviceCmyk), ("b*", PsDeviceRgb), ("b*", PsDeviceCmyk)],
      testCase "a path ended with n paints nothing" $
        paintsOf (onePage "1 0 0 rg 0 0 1 1 re n" [] []) @?= [],
      testCase "cs and the initial colour of an ICCBased space of four components" $
        paintsOf (onePage "/CS0 cs 0 0 1 1 re f" [("ColorSpace", ODict [("CS0", OArr [OName "ICCBased", ORef (extraBase 1)])])] [OStream [("N", OInt 4)] "profile"])
          @?= [page' (PsIccBased 4) ["0", "0", "0", "0"] "f"],
      testCase "cs DeviceCMYK sets its initial colour, scn the components" $
        map paComponents (paintsOf (onePage "/DeviceCMYK cs 0 0 1 1 re f 0 0 0.2 1 scn 0 0 1 1 re f" [] [])) @?= [["0", "0", "0", "1"], ["0", "0", "0.2", "1"]],
      testCase "CS and SCN for the stroke, Separation, DeviceN, Lab, Indexed and Pattern" $
        map
          paSpace
          ( paintsOf
              ( onePage
                  "/Sp CS 0 0 m 1 1 l S /Dn cs 0 0 1 1 re f /Lb cs 0 0 1 1 re f /Ix cs 0 0 1 1 re f /Pattern cs /P1 scn 0 0 1 1 re f"
                  [ ( "ColorSpace",
                      ODict
                        [ ("Sp", OArr [OName "Separation", OName "PANTONE#20185#20C", OName "DeviceCMYK", ORef 99]),
                          ("Dn", OArr [OName "DeviceN", OArr [OName "Cyan", OName "Spot1"], OName "DeviceCMYK", ORef 99]),
                          ("Lb", OArr [OName "Lab", ODict []]),
                          ("Ix", OArr [OName "Indexed", OName "DeviceRGB", OInt 1, OStr "abcdef"])
                        ]
                    )
                  ]
                  []
              )
          )
          @?= [PsSeparation "PANTONE 185 C", PsDeviceN ["Cyan", "Spot1"], PsLab, PsIndexed, PsPattern],
      testCase "a Form XObject inherits the colour of its caller and Do gives it back" $
        summary
          ( onePage
              "0 0 0 1 k /Fm1 Do 0 0 1 1 re f"
              [("XObject", ODict [("Fm1", ORef (extraBase 1))])]
              [OStream [("Type", OName "XObject"), ("Subtype", OName "Form"), ("Resources", ODict [])] "0 0 1 1 re f 1 0 0 rg 0 0 1 1 re f"]
          )
          @?= [ (1, "f", FormXObject ["Fm1"], PsDeviceCmyk, ["0", "0", "0", "1"]),
                (1, "f", FormXObject ["Fm1"], PsDeviceRgb, ["1", "0", "0"]),
                (1, "f", PageContent, PsDeviceCmyk, ["0", "0", "0", "1"])
              ],
      testCase "a Form XObject inside a Form XObject: the names of the resources in order, its own colour spaces" $
        summary
          ( onePage
              "/Fm1 Do"
              [("XObject", ODict [("Fm1", ORef (extraBase 1))])]
              [ OStream [("Type", OName "XObject"), ("Subtype", OName "Form"), ("Resources", ODict [("XObject", ODict [("Fm2", ORef (extraBase 1 + 1))])])] "/Fm2 Do",
                OStream [("Type", OName "XObject"), ("Subtype", OName "Form"), ("Resources", ODict [("ColorSpace", ODict [("G", OArr [OName "ICCBased", ORef (extraBase 1 + 2)])])])] "/G cs 0.3 sc 0 0 1 1 re f",
                OStream [("N", OInt 1)] "profile"
              ]
          )
          @?= [(1, "f", FormXObject ["Fm1", "Fm2"], PsIccBased 1, ["0.3"])],
      testCase "a Form XObject that calls itself is read to a fixed depth" $
        assertBool "finite" (length (paintsOf (onePage "/Fm1 Do" [("XObject", ODict [("Fm1", ORef (extraBase 1))])] [OStream [("Type", OName "XObject"), ("Subtype", OName "Form"), ("Resources", ODict [("XObject", ODict [("Fm1", ORef (extraBase 1))])])] "0 0 1 1 re f /Fm1 Do"])) < 100),
      testCase "an image is not a paint, inline or by Do" $
        paintsOf
          ( onePage
              "1 0 0 rg /Im1 Do BI /W 1 /H 1 /CS /RGB /BPC 8 ID abc EI"
              [("XObject", ODict [("Im1", ORef (extraBase 1))])]
              [OStream [("Type", OName "XObject"), ("Subtype", OName "Image")] "abc"]
          )
          @?= [],
      testCase "the text rendering modes: fill, stroke, both, and none for 3 and 7" $
        map (\p -> (paOperator p, paSpace p)) (paintsOf (onePage "BT /F1 1 Tf 1 0 0 rg 0 0 0 1 K 3 Tr (a) Tj 0 Tr (b) Tj 1 Tr [(c)] TJ 2 Tr (d) ' 7 Tr (e) Tj ET" [] []))
          @?= [("Tj", PsDeviceRgb), ("TJ", PsDeviceCmyk), ("'", PsDeviceRgb), ("'", PsDeviceCmyk)],
      testCase "the text rendering mode is restored by Q" $
        map paOperator (paintsOf (onePage "BT q 3 Tr Q (a) Tj ET" [] [])) @?= ["Tj"],
      testCase "the pages are numbered from 1 in order" $
        map paPage (paintsOf (pdfOf [("0 0 1 1 re f", []), ("", []), ("0 0 1 1 re f 0 0 1 1 re f", [])] [])) @?= [1, 3, 3],
      testCase "the page content as an array of streams, unfiltered" $
        paintsOf
          ( PdfObjects
              "1.6"
              [ ODict [("Type", OName "Catalog"), ("Pages", ORef 2)],
                ODict [("Type", OName "Pages"), ("Kids", OArr [ORef 3]), ("Count", OInt 1)],
                ODict [("Type", OName "Page"), ("Parent", ORef 2), ("Resources", ODict []), ("Contents", OArr [ORef 4, ORef 5])],
                OStream [] "0 0 0 1 k",
                OStream [] "0 0 1 1 re f"
              ]
              (ODict [("Root", ORef 1)])
          )
          @?= [page' PsDeviceCmyk ["0", "0", "0", "1"] "f"],
      testCase "sh paints with the colour space of its shading" $
        map paSpace (paintsOf (onePage "/Sh1 sh" [("Shading", ODict [("Sh1", ODict [("ShadingType", OInt 2), ("ColorSpace", OName "DeviceCMYK")])])] [])) @?= [PsDeviceCmyk],
      -- unembeddedFonts, from the rows of the table of boundaries
      testCase "unembeddedFonts: no font descriptor" $
        unembeddedFonts (onePage "" [] []) @?= [],
      testCase "unembeddedFonts: one descriptor with FontFile3 only" $
        unembeddedFonts (onePage "" [] [descriptor [("FontFile3", ORef 1)]]) @?= [],
      testCase "unembeddedFonts: one descriptor not embedded" $
        unembeddedFonts (onePage "" [] [descriptor []]) @?= ["ABCDEF+Body"],
      testCase "unembeddedFonts: two descriptors of one name, both listed" $
        unembeddedFonts (onePage "" [] [descriptor [], descriptor []]) @?= ["ABCDEF+Body", "ABCDEF+Body"],
      testCase "unembeddedFonts: FontFile and FontFile2 embed" $
        unembeddedFonts (onePage "" [] [descriptor [("FontFile", ORef 1)], descriptor [("FontFile2", ORef 1)]]) @?= [],
      -- spotColorants
      testCase "spotColorants: Separation All alone is none" $
        spotColorants (onePage "" [reg] []) @?= [],
      testCase "spotColorants: Separation None is none" $
        spotColorants (onePage "" [("ColorSpace", ODict [("N", OArr [OName "Separation", OName "None", OName "DeviceGray", ORef 99])])] []) @?= [],
      testCase "spotColorants: one Separation of PANTONE 185 C" $
        spotColorants (onePage "" [("ColorSpace", ODict [("P", OArr [OName "Separation", OName "PANTONE#20185#20C", OName "DeviceCMYK", ORef 99])])] []) @?= ["PANTONE 185 C"],
      testCase "spotColorants: DeviceN [/Cyan /Spot1] is Spot1" $
        spotColorants (onePage "" [("ColorSpace", ODict [("D", OArr [OName "DeviceN", OArr [OName "Cyan", OName "Spot1"], OName "DeviceCMYK", ORef 99])])] []) @?= ["Spot1"],
      testCase "spotColorants: each once, in the order found, used or not, in streams too" $
        spotColorants
          ( onePage
              ""
              [("ColorSpace", ODict [("A", OArr [OName "Separation", OName "Gold", OName "DeviceCMYK", ORef 99]), ("B", OArr [OName "DeviceN", OArr [OName "Silver", OName "Gold", OName "None"], OName "DeviceCMYK", ORef 99])])]
              [OStream [("Resources", ODict [("ColorSpace", ODict [("C", OArr [OName "Separation", OName "Copper", OName "DeviceCMYK", ORef 99])])])] ""]
          )
          @?= ["Gold", "Silver", "Copper"]
    ]
