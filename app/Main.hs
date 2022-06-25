module Main where

import Debug.Trace
import Text.Read
import Text.Printf
import Pdf.Core.File hiding (withPdfFile)
import Pdf.Document
import System.Directory
import System.Console.ANSI
import qualified Data.Text as T
--import Data.Ord
import Data.List

type Market = String
type Price = Maybe Double
type Commodity = String
type CommodityPrice = (Commodity, Price)

data MarketPrice = MarketPrice String Double deriving Show

market :: MarketPrice -> String
market (MarketPrice m _) = m

price :: MarketPrice -> Double
price (MarketPrice _ p) = p

getPrice :: Price -> Double
getPrice (Just x) = x

instance Eq MarketPrice where
    a == b =  market a == market b && price a == price b

instance Ord MarketPrice where
    a `compare` b = 
        let r = price a `compare` price b
        in if r == EQ then market a `compare` market b else r

-- not used, just an attempt to use StateMonad
data Config = Config
    {
        inputDir :: String,
        filePrefix :: String,
        fileExtension :: String
    }

-- not used, just an attempt to abstract data
type PriceRow = [ Price ]

-- not used, just an attempt to abstract data
data PriceTable = PriceTable 
    {
        headers :: [ Commodity ],
        rows :: [ PriceRow ]
    }

-- extraction logic
-- break data into rows
-- break rows into fields
-- get the first field => Market
-- get succeeding fields => Retail Price
-- parse header row to get commodity names

-- global variables
dir :: String
dir = "input"

prefix :: String
prefix = "Price-Monitoring-"

separator :: Int
separator = 200

-- not used but was intended for sorting the filenames
months :: [ String ]
months = [
    "January", 
    "February", 
    "March", 
    "April", 
    "May", 
    "June", 
    "July", 
    "August", 
    "September", 
    "October", 
    "November", 
    "December" ]

-- list of valid commodities
commodities :: [ String ]
commodities = [ 
    "Well_Milled_Rice", 
    "Tilapia", 
    "Galunggong", 
    "Whole_Chicken", 
    "Egg_Medium", 
    "Ampalaya", 
    "Tomato", 
    "Cabbage", 
    "Pechay_Baguio", 
    "Red_Onion" ]

displayAll :: Pdf -> IO ()
displayAll pdf = do
    doc <- document pdf
    catalog <- documentCatalog doc
    rootNode <- catalogPageNode catalog
    page <- pageNodePageByNum rootNode 1
    text <- pageExtractText page
    let noFooter = removeFooter text -- remove footer
    let noExtraLines = T.unpack $ cleanData noFooter -- remove extra lines
    let stringLines = lines noExtraLines -- split into separate lines
    let (h, d) = splitDataToHeaderAndData stringLines -- split header and details
    displayBorder
    let cleanedData = processDataRows h d
    printTable cleanedData
    displayBorder

displayBorder :: IO ()
displayBorder = putStrLn $ replicate separator '*'

-- display prices from all markets for a given commodity
searchAndDisplayResults :: String -> Pdf -> IO ()
searchAndDisplayResults c pdf = do
    doc <- document pdf
    catalog <- documentCatalog doc
    rootNode <- catalogPageNode catalog
    page <- pageNodePageByNum rootNode 1
    text <- pageExtractText page
    let noFooter = removeFooter text
    let noExtraLines = T.unpack $ cleanData noFooter
    let stringLines = lines noExtraLines
    let (h, d) = splitDataToHeaderAndData stringLines
    displayBorder
    let cleanedData = processDataRows h d
    filterAndPrintTable c cleanedData
    displayBorder

-- discard footer text
removeFooter :: T.Text -> T.Text
removeFooter text = fst $ T.breakOn (T.pack "Source:") text

-- list of string replacements
replaceList :: [ (String, String) ]
replaceList = [ 
    ("\nNOT \nAVAILABLE\n"," - "), 
    ("\nWell-milled \nRice (Local)", "Well_Milled_Rice"), 
    ("\nTilapia", " Tilapia"), 
    ("\nWhole \nChicken"," Whole_Chicken"), 
    ("\n*Egg \n(Medium)", " Egg_Medium"), 
    ("\nAmpalaya", " Ampalaya"), 
    ("\nPechay \nBaguio", " Pechay_Baguio "),
    ("\nRed Onion \n(Local)", "Red_Onion") ]

-- converts pair of String to pair of Text
convertToText :: [ (String, String) ] -> [ (T.Text, T.Text) ]
convertToText = map (\x -> (T.pack $ fst x, T.pack $ snd x) )

-- cleans the raw data so it can be properly parsed
cleanData :: T.Text -> T.Text
cleanData = searchAndReplaceAll $ convertToText $ replaceList

-- cleans the raw headers
searchAndReplaceAll :: [(T.Text, T.Text)] -> T.Text -> T.Text
--searchAndReplaceAll [x] text = T.replace (T.pack $ fst x) (T.pack $ snd x) text
--searchAndReplaceAll (x:xs) text = T.replace (T.pack $ fst x) (T.pack $ snd x) (searchAndReplaceAll xs text)
searchAndReplaceAll xs text = foldr (\x -> T.replace (fst x) (snd x)) text xs

-- split headers and markets
splitDataToHeaderAndData :: [String] -> ([String], [String])
splitDataToHeaderAndData xs = 
    let (h, d) = splitAt 1 $ xs
    in (words $ head h, d)

-- split market and data
-- New Las Piñas City Public Market 40.00 140.00 240.00 200.00 6.00 140.00 100.00 80.00 80.00 100.00
-- ([Text],[Text])
splitDataToMarketAndData' :: Int -> String -> ([String], [String])
splitDataToMarketAndData' num text = 
    let tokens = words text
    in splitAt (length tokens - num) tokens

-- convert to proper type
-- (Market, [Price])
-- ("New Las Piñas City Public Market", [Maybe 40.00, Maybe 140.00, Maybe 240.00, ...])
splitDataToMarketAndData :: [String] -> String -> (Market, [CommodityPrice])
splitDataToMarketAndData headers text = 
    let (m, d) = splitDataToMarketAndData' (length headers) text
    in (unwords m, zip headers $ map (\x -> readMaybe $ x) d)

processDataRows :: [String] -> [String] -> [(Market, [CommodityPrice])]
processDataRows headers rows = map (\x -> splitDataToMarketAndData headers x) rows

toMarketPrice :: [(Market, [CommodityPrice])] -> [MarketPrice]
toMarketPrice xs = map (\x -> MarketPrice (fst x) (getPrice $ (snd.head.snd) x)) xs

filterAndPrintTable :: String -> [(Market, [CommodityPrice])] -> IO ()
filterAndPrintTable s xs = do
    let ys = filter (\x -> (snd x) /= []) $ map (\x -> (fst x, filterCommodity s $ snd x) ) xs
    mapM (\x -> printf "%-80s %.2f\n" (market x) (price x)) $ sort $ toMarketPrice ys
    return ()

-- find the commodity from the list
filterCommodity :: String -> [CommodityPrice] -> [CommodityPrice]
filterCommodity s xs = filter (\x -> (fst x) == s && (snd x) /= Nothing) xs

-- print the whole price list
printTable :: [(Market, [CommodityPrice])] -> IO ()
printTable xs = do
    mapM printMarket xs
    return ()

-- print a single market
printMarket :: (Market, [CommodityPrice]) -> IO ()
printMarket p = do
    putStrLn $ fst p
    mapM (\x -> putStrLn $ "\t" ++ show x) (snd p)
    return ()

printMenu :: IO ()
printMenu = do
    putStrLn ""
    putStrLn "*******************"
    putStrLn "* Commands        *"
    putStrLn "*******************"
    putStrLn "* 1 - Files       *"
    putStrLn "* 2 - Commodities *"
    putStrLn "* 3 - Query       *"
    putStrLn "* 4 - Display     *"
    putStrLn "* 5 - Exit        *"
    putStrLn "*******************"
    putStrLn "Enter choice:"

printHelper :: [(Int, String)] -> IO ()
printHelper [] = return ()
printHelper (x:xs) = do
    putStrLn $ show (fst x) ++ ") " ++ (snd x)
    printHelper xs

printFiles :: IO ()
printFiles = do
    files <- listDirectory dir
    putStrLn ""
    putStrLn "[Files]"
    printHelper $ zip [1..] $ map getDateFromFile files

printCommodities :: IO ()
printCommodities = do
    mapM putStrLn commodities
    return ()

printSearch :: IO ()
printSearch = do
    putStrLn ""
    putStrLn "Enter date to search: "
    file <- getLine
    putStrLn "Enter commodity: "
    commodity <- getLine
    if commodity `elem` commodities then searchCommodity file commodity else putStrLn "ERROR: Invalid commodity"
    return ()

printDate :: IO ()
printDate = do
    putStrLn ""
    putStrLn "Enter date to search: "
    file <- getLine
    let filepath = (getFilePath . getFileFromDate) file
    exists <- doesFileExist filepath
    if exists then withPdfFile filepath displayAll
    else putStrLn "File not found."
    return ()    

searchCommodity :: String -> String -> IO ()
searchCommodity dt cm = do
    let filepath = (getFilePath . getFileFromDate) dt
    exists <- doesFileExist filepath
    if exists then searchCommodityInFile filepath cm 
    else putStrLn "File not found."

searchCommodityInFile :: FilePath -> String -> IO ()
searchCommodityInFile f c = do
    withPdfFile f (searchAndDisplayResults c)

-- removes the filename prefix and extension to get the date
getDateFromFile :: String -> String
getDateFromFile s =
    let l = length s - 4
        p = length prefix
    in drop p $ take l s

-- prepends the filename prefix and appends the extension to the date 
getFileFromDate :: String -> String
getFileFromDate s = prefix ++ s ++ ".pdf"

-- prepends the directory where PDF files are stored, move this to StateMonad
getFilePath :: String -> String
getFilePath s = dir ++ "/" ++ s

main :: IO ()
main = do
    printMenu
    choice <- getLine
    case choice of
        "1" -> do
            clearScreen
            printFiles
            main
        "2" -> do
            clearScreen
            printCommodities
            main
        "3" -> do
            printSearch
            main
        "4" -> do
            printDate
            main            
        "5" -> do
            putStrLn "\nTHAT'S ALL FOLKS"
            return ()
        otherwise -> main
