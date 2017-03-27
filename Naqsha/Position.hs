{-# LANGUAGE CPP                        #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE Rank2Types                 #-}
{-# LANGUAGE TemplateHaskell            #-}
-- | This module captures position of a point on the globe.
module Naqsha.Position
       ( -- * Latitude, longitude and geopositions.
         -- $latandlong$
         Latitude, Longitude, Geo(..), GeoBounds(..), maxLatitude, maxLongitude, minLatitude, minLongitude
       , Location(..)
         -- ** Some common latitude
       , equator, northPole, southPole
         -- ** Some common longitude
       , greenwich
         -- * Angles and angular quantities.
       , Angle, Angular(..)
         -- ** Distance calculation.
       , dHvS, dHvS', rMean
       ) where

import           Control.Lens
import           Control.Monad               ( liftM )
import           Data.Default
import           Data.Int
import           Data.List                   ( unfoldr )
import           Data.Monoid
import           Data.Group
import           Data.Vector.Unboxed         ( MVector(..), Vector, Unbox)
import qualified Data.Vector.Generic         as GV
import qualified Data.Vector.Generic.Mutable as GVM

import           Prelude         -- To avoid redundunt import warnings.

-- $latandlong$
--
-- A point on the globe is specified by giving its geo coordinates
-- captures by the type `Geo`.  It is essentially a pair of the
-- `Latitude` and `Longitude` of the point.
--
-- Latitude and Longitude are instances of the class `Angular`. So the
-- can be expressed in either degrees or radians using `deg` or `rad`
-- respectively.
--
-- > kanpurLatitude  :: Latitude
-- > kanpurLatitude  = deg 26.4477777
-- > kanpurLongitude :: Longitude
-- > kanpurLongitude = deg 80.3461111
--
-- Latitudes and longitudes are instances of `Monoid` where the monoid
-- instance adds up the angle. One can use this `Monoid` instance to
-- express in degrees, minutes and seconds as follows
--
-- > kanpurLatitude  = deg 26 <> minute 26 <> second 52
-- > kanpurLongitude = deg 80 <> minute 20 <> second 46
--
-- They are also instances of `Group` where `invert` is the angle in
-- the opposite direction, i.e for latitudes, `invert` converts from
-- North to South and vice-versa and for longitudes `invert` converts
-- from East to West. Be careful with negative quantities though. To
-- express a latitude of -1° 2′ 3″ one should use
--
-- > someNegLatitude :: Latitude
-- > someNegLatitude = invert $ deg 1 <> minute 2 <> second 3  -- correct
--
-- and not
--
-- > someNegLatitude = deg (-1) <> minute 2 <> second 3  -- wrong
--
-- We would like to attach additional information with geographic
-- locations. The type class `Location` captures all types that have
-- an associated geographical coordinates.

----------------------------- Lattitude ----------------------------------

-- | The latitude of a point. Positive denotes North of Equator where as negative
-- South.

newtype Latitude = Latitude { unLat :: Angle }

instance Show Latitude where
  show = show . unLat

instance Angular Latitude where
  deg         = normalise . Latitude . deg
  toDeg       = toDeg     . unLat
  normalise   = Latitude  . Angle . normLat . unAngle . unLat

instance Eq Latitude where
  (==) l1 l2 = unAngle (unLat $ normalise l1) == unAngle (unLat $ normalise l2)

instance Monoid Latitude where
  mempty      = equator
  mappend x y = normalise $ Latitude $ Angle $ unAngle (unLat x)  + unAngle (unLat y)

instance Group Latitude where
  invert  = Latitude . Angle . negate . unAngle . unLat . normalise

instance Default Latitude where
  def = Latitude $ Angle 0

-- | The latitude of equator.
equator :: Latitude
equator = Latitude $ Angle 0

-- | The latitude of north pole.
northPole :: Latitude
northPole = Latitude $ Angle 90

-- | The latitude of south pole.
southPole :: Latitude
southPole = Latitude $ Angle (-90)

-------------------------- Longitude ------------------------------------------

-- | The longitude of a point. Positive denotes East of the Greenwich meridian
-- where as negative denotes West.
newtype Longitude = Longitude { unLong :: Angle }


instance Default Longitude where
  def = Longitude $ Angle 0

instance Show Longitude where
  show = show . unLong

instance Angular Longitude where
  deg       = normalise . Longitude . deg
  toDeg     = toDeg     . unLong
  normalise = Longitude . Angle .  normLong . unAngle . unLong

instance Eq Longitude  where
  (==) l1 l2 = unAngle (unLong $ normalise l1) == unAngle (unLong $ normalise l2)

instance Monoid Longitude where
  mempty      = greenwich
  mappend x y = normalise $ Longitude $ Angle $ unAngle (unLong x)  + unAngle (unLong y)


instance Group Longitude where
  invert  = Longitude . Angle . negate . unAngle . unLong . normalise

-- | The zero longitude.
greenwich :: Longitude
greenwich = Longitude $ Angle 0

-- | The coordinates of a point on the earth's surface.
data Geo = Geo {-# UNPACK #-} !Latitude
               {-# UNPACK #-} !Longitude


instance Monoid Geo where
  mempty      = Geo mempty mempty
  mappend (Geo xlat xlong) (Geo ylat  ylong) = Geo (xlat `mappend` ylat) (xlong `mappend` ylong)

instance Group Geo where
  invert (Geo lt lg) = Geo (invert lt) $ invert lg

instance Default Geo where
  def = Geo def def

-- | Objects that have a location on the globe. Minimum complete
-- implementation: either the two functions `longitude` and `latitude`
-- or the single function `geoPosition`.
class Location a where
  -- | The latitude of the object.
  latitude    :: Lens' a Latitude

  -- | The longitude of the object.
  longitude   :: Lens' a Longitude

  -- | The geo-Position of the object.
  geoPosition :: Lens' a Geo

  latitude = geoPosition . latitude

  longitude = geoPosition . longitude

----------------------------- Angles and Angular quantities -----------------------

-- | An abstract angle measured in degrees up to some precision (system dependent).
newtype Angle = Angle {unAngle ::  Int64} deriving Unbox

-- | The scaling used to represent angles.
scale :: Int64
scale = 10000000

threeSixty :: Int64
threeSixty = 360 * scale

ninety     :: Int64
ninety     = 90 * scale

twoSeventy :: Int64
twoSeventy = 270 * scale

oneEighty  :: Int64
oneEighty  = 180 * scale



scaleDouble :: Double
scaleDouble = fromIntegral scale

instance Angular Angle where
  deg       = Angle . truncate . (*scaleDouble)
  toDeg     = (/scaleDouble) . fromIntegral .  unAngle
  normalise = id
  {-# INLINE normalise #-}


instance Enum Angle where
  toEnum    = Angle . (*scale) . toEnum
  fromEnum  = fromEnum . flip quot scale . unAngle


instance Show Angle where
  show x | r == 0    = show q
         | otherwise = show q ++ "." ++ concatMap show (unfoldr unfoldDigits (abs r, scale `quot` 10))
    where (q,r) = unAngle x `quotRem` scale
          unfoldDigits (v, p)
            | v ==  0   = Nothing
            | p >= 1    = Just (v',(r', p `quot` 10))
            | otherwise = Nothing
            where (v',r') = v `quotRem` p


-- | Measurements that are angular. Minimal complete implemenation
-- give one of `deg` or `rad`, one of `toDeg` or `toRad`.
class Angular a where

  -- | Express angular quantity in degrees.
  deg   :: Double -> a

  -- | Express angular quantity in minutes.
  minute :: Double -> a

  -- | Express angular quantity in seconds.
  second :: Double -> a

  -- | Express angular quantity in radians
  rad  :: Double -> a

  -- | Get the angle in degree
  toDeg :: a  -> Double

  -- | Get the angle in radians.
  toRad :: a -> Double

  -- | Normalise the quantity
  normalise  :: a -> a


  rad    = deg . (/180) . (pi*)
  deg    = rad . (/pi)  . (180*)

  toDeg  = (/pi)  . (180*) . toRad
  toRad  = (/180) . (pi*)  . toDeg

  minute = deg . (/60)
  second = deg . (/3600)





instance Location Geo where
  latitude  = lens getter setter
    where setter (Geo _ lo) la = Geo la lo
          getter (Geo la _)    = la

  longitude = lens (\ (Geo _ lo) -> lo) (\ (Geo la _) lo -> Geo la lo)
  geoPosition  = lens id (\ _ x -> x)


instance Eq Geo where
  (==) (Geo xlat xlong) (Geo ylat ylong)
    | xlat == northPole = ylat == northPole  -- longitude irrelevant for north pole
    | xlat == southPole = ylat == southPole  -- longitude irrelevant for south pole
    | otherwise         = xlat == ylat && xlong == ylong

--------------------- Distance calculation -------------------------------------

-- | Mean earth radius in meters. This is the radius used in the
-- haversine formula of `dHvs`.
rMean  :: Double
rMean = 637100.88


-- | This combinator computes the distance (in meters) between two geo-locations
-- using the haversine distance between two points. For `Position` which have an
dHvS :: ( Location geo1
        , Location geo2
        )
      => geo1   -- ^ Point 1
      -> geo2   -- ^ Point 2
      -> Double -- ^ Distance in meters.
dHvS = dHvS' rMean

{-# SPECIALISE dHvS :: Geo      -> Geo      -> Double #-}

-- | A generalisation of `dHvS` that takes the radius as
-- argument. Will work on Mars for example once we set up a latitude
-- longitude system there. For this function units does not matter ---
-- the computed distance is in the same unit as the input radius. We have
--
-- > dHvS = dHvS' rMean
--
dHvS' :: ( Location geo1
         , Location geo2
         )
      => Double  -- ^ Radius (in whatever unit)
      -> geo1     -- ^ Point 1
      -> geo2     -- ^ Point 2
      -> Double
{-# SPECIALISE dHvS' :: Double -> Geo      -> Geo      -> Double #-}
dHvS' r g1 g2 = r * c
  where p1    = toRad $ g1 ^. latitude
        l1    = toRad $ g1 ^. longitude
        p2    = toRad $ g2 ^. latitude
        l2    = toRad $ g2 ^. longitude
        dp    = p2 - p1
        dl    = l2 - l1
        a     = sin (dp/2.0) ^ (2 :: Int) + cos p1 * cos p2 * (sin (dl/2) ^ (2 :: Int))
        c     = 2 * atan2 (sqrt a) (sqrt (1 - a))

--------------------------- Internal helper functions ------------------------


-- | Function to normalise latitudes. It essentially is a saw-tooth
-- function of period 360 with max values 90.
normLat :: Int64 -> Int64
normLat y = signum y * normPosLat (abs y)

-- | Normalise a positive latitude.
normPosLat :: Int64 -> Int64
normPosLat x | r <= ninety     =  r
             | r <= twoSeventy =  oneEighty - r
             | otherwise       =  r  - threeSixty
    where r  = x `rem` threeSixty



-- | Function to normalise longitude.
normLong :: Int64 -> Int64
normLong y = signum y * normPosLong (abs y)

-- | Normalise a positive longitude.
normPosLong :: Int64 -> Int64
normPosLong x | r <= oneEighty  = r
              | otherwise       = r - threeSixty
  where r   = x `rem` threeSixty


------------------- Making stuff suitable for unboxed vector. --------------------------

newtype instance MVector s Angle = MAngV  (MVector s Int64)
newtype instance Vector    Angle = AngV   (Vector Int64)

newtype instance MVector s Latitude = MLatV (MVector s Angle)
newtype instance Vector    Latitude = LatV  (Vector Angle)


newtype instance MVector s Longitude = MLongV (MVector s Angle)
newtype instance Vector    Longitude = LongV  (Vector Angle)


newtype instance MVector s Geo = MGeoV (MVector s (Angle,Angle))
newtype instance Vector    Geo = GeoV  (Vector    (Angle,Angle))


-------------------- Instance for Angle --------------------------------------------

instance GVM.MVector MVector Angle where
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicOverlaps #-}
  {-# INLINE basicUnsafeNew #-}
  {-# INLINE basicUnsafeReplicate #-}
  {-# INLINE basicUnsafeRead #-}
  {-# INLINE basicUnsafeWrite #-}
  {-# INLINE basicClear #-}
  {-# INLINE basicSet #-}
  {-# INLINE basicUnsafeCopy #-}
  {-# INLINE basicUnsafeGrow #-}
  basicLength          (MAngV v)          = GVM.basicLength v
  basicUnsafeSlice i n (MAngV v)          = MAngV $ GVM.basicUnsafeSlice i n v
  basicOverlaps (MAngV v1) (MAngV v2)     = GVM.basicOverlaps v1 v2

  basicUnsafeRead  (MAngV v) i            = Angle `liftM` GVM.basicUnsafeRead v i
  basicUnsafeWrite (MAngV v) i (Angle x)  = GVM.basicUnsafeWrite v i x

  basicClear (MAngV v)                    = GVM.basicClear v
  basicSet   (MAngV v)         (Angle x)  = GVM.basicSet v x

  basicUnsafeNew n                        = MAngV `liftM` GVM.basicUnsafeNew n
  basicUnsafeReplicate n     (Angle x)    = MAngV `liftM` GVM.basicUnsafeReplicate n x
  basicUnsafeCopy (MAngV v1) (MAngV v2)   = GVM.basicUnsafeCopy v1 v2
  basicUnsafeGrow (MAngV v)   n           = MAngV `liftM` GVM.basicUnsafeGrow v n

#if MIN_VERSION_vector(0,11,0)
  basicInitialize (MAngV v)               = GVM.basicInitialize v
#endif

instance GV.Vector Vector Angle where
  {-# INLINE basicUnsafeFreeze #-}
  {-# INLINE basicUnsafeThaw #-}
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicUnsafeIndexM #-}
  {-# INLINE elemseq #-}
  basicUnsafeFreeze (MAngV v)         = AngV  `liftM` GV.basicUnsafeFreeze v
  basicUnsafeThaw (AngV v)            = MAngV `liftM` GV.basicUnsafeThaw v
  basicLength (AngV v)                = GV.basicLength v
  basicUnsafeSlice i n (AngV v)       = AngV $ GV.basicUnsafeSlice i n v
  basicUnsafeIndexM (AngV v) i        = Angle   `liftM`  GV.basicUnsafeIndexM v i

  basicUnsafeCopy (MAngV mv) (AngV v) = GV.basicUnsafeCopy mv v
  elemseq _ (Angle x)                 = GV.elemseq (undefined :: Vector a) x


-------------------- Instance for latitude --------------------------------------------

instance GVM.MVector MVector Latitude where
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicOverlaps #-}
  {-# INLINE basicUnsafeNew #-}
  {-# INLINE basicUnsafeReplicate #-}
  {-# INLINE basicUnsafeRead #-}
  {-# INLINE basicUnsafeWrite #-}
  {-# INLINE basicClear #-}
  {-# INLINE basicSet #-}
  {-# INLINE basicUnsafeCopy #-}
  {-# INLINE basicUnsafeGrow #-}
  basicLength          (MLatV v)              = GVM.basicLength v
  basicUnsafeSlice i n (MLatV v)              = MLatV $ GVM.basicUnsafeSlice i n v
  basicOverlaps (MLatV v1) (MLatV v2)         = GVM.basicOverlaps v1 v2

  basicUnsafeRead  (MLatV v) i                = Latitude `liftM` GVM.basicUnsafeRead v i
  basicUnsafeWrite (MLatV v) i (Latitude x)   = GVM.basicUnsafeWrite v i x

  basicClear (MLatV v)                        = GVM.basicClear v
  basicSet   (MLatV v)         (Latitude x)   = GVM.basicSet v x

  basicUnsafeNew n                            = MLatV `liftM` GVM.basicUnsafeNew n
  basicUnsafeReplicate n     (Latitude x)     = MLatV `liftM` GVM.basicUnsafeReplicate n x
  basicUnsafeCopy (MLatV v1) (MLatV v2)       = GVM.basicUnsafeCopy v1 v2
  basicUnsafeGrow (MLatV v)   n               = MLatV `liftM` GVM.basicUnsafeGrow v n

#if MIN_VERSION_vector(0,11,0)
  basicInitialize (MLatV v)                   = GVM.basicInitialize v
#endif

instance GV.Vector Vector Latitude where
  {-# INLINE basicUnsafeFreeze #-}
  {-# INLINE basicUnsafeThaw #-}
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicUnsafeIndexM #-}
  {-# INLINE elemseq #-}
  basicUnsafeFreeze (MLatV v)         = LatV  `liftM` GV.basicUnsafeFreeze v
  basicUnsafeThaw (LatV v)            = MLatV `liftM` GV.basicUnsafeThaw v
  basicLength (LatV v)                = GV.basicLength v
  basicUnsafeSlice i n (LatV v)       = LatV $ GV.basicUnsafeSlice i n v
  basicUnsafeIndexM (LatV v) i        = Latitude   `liftM`  GV.basicUnsafeIndexM v i

  basicUnsafeCopy (MLatV mv) (LatV v) = GV.basicUnsafeCopy mv v
  elemseq _ (Latitude x)              = GV.elemseq (undefined :: Vector a) x


-------------------------------- Instance for Longitude -----------------------------------

instance GVM.MVector MVector Longitude where
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicOverlaps #-}
  {-# INLINE basicUnsafeNew #-}
  {-# INLINE basicUnsafeReplicate #-}
  {-# INLINE basicUnsafeRead #-}
  {-# INLINE basicUnsafeWrite #-}
  {-# INLINE basicClear #-}
  {-# INLINE basicSet #-}
  {-# INLINE basicUnsafeCopy #-}
  {-# INLINE basicUnsafeGrow #-}
  basicLength          (MLongV v)             = GVM.basicLength v
  basicUnsafeSlice i n (MLongV v)             = MLongV $ GVM.basicUnsafeSlice i n v
  basicOverlaps (MLongV v1) (MLongV v2)       = GVM.basicOverlaps v1 v2

  basicUnsafeRead  (MLongV v) i               = Longitude `liftM` GVM.basicUnsafeRead v i
  basicUnsafeWrite (MLongV v) i (Longitude x) = GVM.basicUnsafeWrite v i x

  basicClear (MLongV v)                       = GVM.basicClear v
  basicSet   (MLongV v)         (Longitude x) = GVM.basicSet v x

  basicUnsafeNew n                             = MLongV `liftM` GVM.basicUnsafeNew n
  basicUnsafeReplicate n     (Longitude x)     = MLongV `liftM` GVM.basicUnsafeReplicate n x
  basicUnsafeCopy (MLongV v1) (MLongV v2)      = GVM.basicUnsafeCopy v1 v2
  basicUnsafeGrow (MLongV v)   n               = MLongV `liftM` GVM.basicUnsafeGrow v n

#if MIN_VERSION_vector(0,11,0)
  basicInitialize (MLongV v)                   = GVM.basicInitialize v
#endif

instance GV.Vector Vector Longitude where
  {-# INLINE basicUnsafeFreeze #-}
  {-# INLINE basicUnsafeThaw #-}
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicUnsafeIndexM #-}
  {-# INLINE elemseq #-}
  basicUnsafeFreeze (MLongV v)          = LongV  `liftM` GV.basicUnsafeFreeze v
  basicUnsafeThaw (LongV v)             = MLongV `liftM` GV.basicUnsafeThaw v
  basicLength (LongV v)                 = GV.basicLength v
  basicUnsafeSlice i n (LongV v)        = LongV $ GV.basicUnsafeSlice i n v
  basicUnsafeIndexM (LongV v) i         = Longitude   `liftM`  GV.basicUnsafeIndexM v i

  basicUnsafeCopy (MLongV mv) (LongV v) = GV.basicUnsafeCopy mv v
  elemseq _ (Longitude x)               = GV.elemseq (undefined :: Vector a) x


----------------------------- Instance for Geo ---------------------------------------------

instance GVM.MVector MVector Geo where
  {-# INLINE basicLength          #-}
  {-# INLINE basicUnsafeSlice     #-}
  {-# INLINE basicOverlaps        #-}
  {-# INLINE basicUnsafeNew       #-}
  {-# INLINE basicUnsafeReplicate #-}
  {-# INLINE basicUnsafeRead      #-}
  {-# INLINE basicUnsafeWrite     #-}
  {-# INLINE basicClear           #-}
  {-# INLINE basicSet             #-}
  {-# INLINE basicUnsafeCopy      #-}
  {-# INLINE basicUnsafeGrow      #-}
  basicLength          (MGeoV v)         = GVM.basicLength v
  basicUnsafeSlice i n (MGeoV v)         = MGeoV $ GVM.basicUnsafeSlice i n v
  basicOverlaps (MGeoV v1) (MGeoV v2)    = GVM.basicOverlaps v1 v2

  basicUnsafeRead  (MGeoV v) i           = do (x,y) <- GVM.basicUnsafeRead v i
                                              return $ Geo (Latitude x) $ Longitude y
  basicUnsafeWrite (MGeoV v) i (Geo x y) = GVM.basicUnsafeWrite v i (unLat x, unLong y)

  basicClear (MGeoV v)                   = GVM.basicClear v
  basicSet   (MGeoV v)         (Geo x y) = GVM.basicSet v (unLat x, unLong y)

  basicUnsafeNew n                       = MGeoV `liftM` GVM.basicUnsafeNew n
  basicUnsafeReplicate n     (Geo x y)   = MGeoV `liftM` GVM.basicUnsafeReplicate n (unLat x, unLong y)
  basicUnsafeCopy (MGeoV v1) (MGeoV v2)  = GVM.basicUnsafeCopy v1 v2
  basicUnsafeGrow (MGeoV v)   n          = MGeoV `liftM` GVM.basicUnsafeGrow v n

#if MIN_VERSION_vector(0,11,0)
  basicInitialize (MGeoV v)              = GVM.basicInitialize v
#endif

instance GV.Vector Vector Geo where
  {-# INLINE basicUnsafeFreeze #-}
  {-# INLINE basicUnsafeThaw #-}
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicUnsafeIndexM #-}
  {-# INLINE elemseq #-}
  basicUnsafeFreeze (MGeoV v)         = GeoV  `liftM` GV.basicUnsafeFreeze v
  basicUnsafeThaw (GeoV v)            = MGeoV `liftM` GV.basicUnsafeThaw v
  basicLength (GeoV v)                = GV.basicLength v
  basicUnsafeSlice i n (GeoV v)       = GeoV $ GV.basicUnsafeSlice i n v
  basicUnsafeIndexM (GeoV v) i        =do (x,y) <- GV.basicUnsafeIndexM v i
                                          return $ Geo (Latitude x) $ Longitude y

  basicUnsafeCopy (MGeoV mv) (GeoV v) = GV.basicUnsafeCopy mv v
  elemseq _ (Geo x y)                 = GV.elemseq (undefined :: Vector a) (unLat x, unLong y)




-- | A boundary on earth given by the range of latitude and
-- longitude. We represent this as a pair of Geo coordinates. The
-- `minGeo` given the minimum latitude and longitude, whereas `maxGeo`
-- gives the maximum latitude and longitude. If we visualise it as a
-- rectangle (which is not really accurate because we are on a globe),
-- `minGeo` gives the left bottom corner and `maxGeo` gives the right
-- upper corner.
data GeoBounds = GeoBounds { __maxLatitude  :: Latitude
                           , __minLatitude  :: Latitude
                           , __maxLongitude :: Longitude
                           , __minLongitude :: Longitude
                           }

makeLenses ''GeoBounds

-- | The upperbound on latitude
maxLatitude :: Lens' GeoBounds Latitude
maxLatitude = _maxLatitude

-- | The lowerbound on latitude
minLatitude :: Lens' GeoBounds Latitude
minLatitude = _minLatitude

-- | The upperbound on longitude
maxLongitude :: Lens' GeoBounds Longitude
maxLongitude = _maxLongitude

-- | The lowerbound on longitude
minLongitude :: Lens' GeoBounds Longitude
minLongitude = _minLongitude


instance Default GeoBounds where
  def = GeoBounds def def def def
