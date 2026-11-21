module Test.Nihongo.Terminal.ImageSpec (spec) where

import Data.ByteString.Char8 qualified as BS8
import Nihongo.Terminal.Geometry (TerminalGeometry (..))
import Nihongo.Terminal.Image
  ( Placement (..),
    RowLayout (..),
    SideLayout (..),
    buildKittyStream,
    rowLayout,
    sideLayout,
  )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- | A 120x50 terminal with 8x16 pixel cells.
roomy :: TerminalGeometry
roomy =
  TerminalGeometry
    { termRows = 50,
      termCols = 120,
      cellWidthPx = 8,
      cellHeightPx = 16
    }

spec :: Spec
spec = do
  describe "Nihongo.Terminal.Image.sideLayout" $ do
    it "sizes a square image from the cell aspect ratio" $
      sideLayout roomy 12
        `shouldBe` Just
          SideLayout
            { sideImageRows = 20,
              sideImageCols = 40,
              sideTextCol = 42,
              sideBlockRows = 20
            }

    it "lets a long stroke list run past the bottom of the image" $
      fmap sideBlockRows (sideLayout roomy 29) `shouldBe` Just 29

    it "shrinks the image to fit a short terminal" $
      fmap sideImageRows (sideLayout roomy {termRows = 14} 3) `shouldBe` Just 12

    it "gives up when the image would be too small to read" $
      sideLayout roomy {termRows = 9} 3 `shouldBe` Nothing

    it "gives up when the block would not fit on screen" $
      sideLayout roomy {termRows = 30} 30 `shouldBe` Nothing

    it "gives up when there is no room for the text column" $
      sideLayout roomy {termCols = 60} 3 `shouldBe` Nothing

  describe "Nihongo.Terminal.Image.buildKittyStream" $ do
    it "keeps the stacked escape unchanged" $
      buildKittyStream (Placement 20 Nothing False) ["AAAA"]
        `shouldBe` "\ESC_Ga=T,f=100,t=d,r=20,m=0;AAAA\ESC\\"

    it "adds columns and holds the cursor for side-by-side placement" $ do
      let s = buildKittyStream (Placement 20 (Just 40) True) ["AAAA", "BBBB"]
      s `shouldSatisfy` BS8.isPrefixOf "\ESC_Ga=T,f=100,t=d,r=20,c=40,C=1,m=1;AAAA\ESC\\"
      s `shouldSatisfy` BS8.isSuffixOf "\ESC_Gm=0;BBBB\ESC\\"

  describe "Nihongo.Terminal.Image.rowLayout" $ do
    it "keeps full size when the word fits on one line" $
      rowLayout roomy 2
        `shouldBe` Just
          RowLayout
            { rowImageRows = 20,
              rowImageCols = 40,
              rowStride = 42,
              rowPerLine = 2
            }

    it "shrinks the images a little to keep a word on one line" $
      rowLayout roomy {termCols = 80} 2
        `shouldBe` Just
          RowLayout
            { rowImageRows = 19,
              rowImageCols = 38,
              rowStride = 40,
              rowPerLine = 2
            }

    it "wraps at full size rather than shrink past readability" $
      fmap (\l -> (rowImageRows l, rowPerLine l)) (rowLayout roomy 5) `shouldBe` Just (20, 2)

    it "always places at least one image per line" $
      fmap rowPerLine (rowLayout roomy {termCols = 41} 1) `shouldBe` Just 1

    it "gives up when a single image is wider than the terminal" $
      rowLayout roomy {termCols = 39} 1 `shouldBe` Nothing
