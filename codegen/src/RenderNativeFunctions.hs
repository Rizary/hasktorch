{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE QuasiQuotes #-}
module RenderNativeFunctions where

import Data.Yaml

import qualified Data.Yaml as Y
import Text.Shakespeare.Text (st)
import Data.Text (Text)
import qualified Data.Text.IO as T
import qualified Data.List as L

import ParseNativeFunctions
import ParseFunctionSig as P
import RenderCommon

data NativeFunctionType
  = Common
  | Cpu
  | Cuda
  | SparseCpu
  | SparseCuda
  deriving (Show,Eq)


{-

From native_function.yaml
- func: add(Tensor self, Tensor other, *, Scalar alpha=1) -> Tensor
  matches_jit_signature: True
  variants: function, method

- func: add_(Tensor(a!) self, Tensor other, *, Scalar alpha=1) -> Tensor(a!)
  matches_jit_signature: True
  variants: method

# For C++ only, until we have conversion from C++ numbers to Tensor
- func: add(Tensor self, Tensor other, *, Scalar alpha=1, Tensor(a!) out) -> Tensor(a!)
  matches_jit_signature: True

- func: add(Tensor self, Scalar other, Scalar alpha=1) -> Tensor
  matches_jit_signature: True
  variants: function, method

- func: add_(Tensor(a!) self, Scalar other, Scalar alpha=1) -> Tensor(a!)
  matches_jit_signature: True
  variants: method

From NativeFunction.h(C++)
CAFFE2_API Tensor add(const Tensor & self, const Tensor & other, Scalar alpha=1);
CAFFE2_API Tensor & add_(Tensor & self, const Tensor & other, Scalar alpha=1);

-- see : https://github.com/pytorch/pytorch/blob/9101dfc57ccb6b6931b4e80233bbc64d9080d2e8/aten/src/ATen/native_parse.py#L159-L178
CAFFE2_API Tensor & add_out(Tensor & out, const Tensor & self, const Tensor & other, Scalar alpha=1);

CAFFE2_API Tensor add(const Tensor & self, Scalar other, Scalar alpha=1);
CAFFE2_API Tensor & add_(Tensor & self, Scalar other, Scalar alpha=1);
-}

removeStarArgument :: (NativeFunctionType, Function) -> Function
removeStarArgument (typ',fn) =
  if arguments_out /= []
  then fn {parameters = new_params, name = (name fn) ++ (if typ' == Common then "_out" else "") }
  else fn
  where
    params = parameters fn
    splitByStar [] _ = ([],[])
    splitByStar (Star:xs) (y,y') = (y,y'++xs)
    splitByStar (x:xs) (y,y') = splitByStar xs (y++[x],y')
    (front_star,back_star) = splitByStar params ([],[])
    arguments_out = filter (\v -> ptype v == TenType TensorA' || ptype v == TenType TensorAQ' ) back_star
    arguments_other = filter (\v -> ptype v /= TenType TensorA' && ptype v /= TenType TensorAQ') back_star
    new_params = arguments_out ++ front_star ++ arguments_other


getTypeAndName :: NativeFunction' -> [(NativeFunctionType,Function)]
getTypeAndName nf =
  case dispatch' nf of
    Nothing -> [(Common,func' nf)]
    Just d -> map (\(typ',f) -> (typ',(func' nf){name=f})) (uniqFunctions d)
  where
    uniqFunctions d = L.nub $ concat $
      [ case cpu d of
          Nothing -> []
          Just c -> [(Cpu,c)]
      , case cuda d of
          Nothing -> []
          Just c -> [(Cuda,c)]
      , case sparseCPU d of
          Nothing -> []
          Just c -> [(SparseCpu,c)]
      , case sparseCUDA d of
          Nothing -> []
          Just c -> [(SparseCuda,c)]
      ]

renderFunctions :: NativeFunctionType -> [NativeFunction'] -> Text
renderFunctions typ' nfs = mconcat $ map (functionToCpp True "at::native::") $ map removeStarArgument filtered
  where
    filtered = filter (\(t,_) -> t == typ') $ concat $ map getTypeAndName nfs

typeTemplate :: Text
typeTemplate = [st|
-- generated by using spec/native_functions_modified.yaml and deps/libtorch/include/ATen/NativeFunctions.h

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

module Aten.NativeFunctions.Type where

import qualified Language.C.Inline.Cpp as C
import qualified Language.C.Inline.Cpp.Exceptions as C
import qualified Language.C.Inline.Context as C
import qualified Language.C.Types as C
import qualified Data.Map as Map

import Foreign.C.String
import Foreign.C.Types
import Foreign

data Scalar
data Tensor
data TensorOptions
data TensorList
data TensorAVector
data IndexTensor
data IntList
data StdArray a b
data ScalarType
data SparseTensorRef

data StdString
data Generator
data Device
data Storage

typeTable = Map.fromList [
        (C.TypeName "at::Scalar", #{bra}t|Scalar|#{cket})
      , (C.TypeName "at::Tensor", #{bra}t|Tensor|#{cket})
      , (C.TypeName "at::TensorOptions", #{bra}t|TensorOptions|#{cket})
      , (C.TypeName "at::TensorList", #{bra}t|TensorList|#{cket})
      , (C.TypeName "at::IndexTensor", #{bra}t|IndexTensor|#{cket})
      , (C.TypeName "at::IntArrayRef", #{bra}t|IntList|#{cket})
      , (C.TypeName "at::ScalarType", #{bra}t|ScalarType|#{cket})
      , (C.TypeName "at::SparseTensorRef", #{bra}t|SparseTensorRef|#{cket})
      , (C.TypeName "at::Storage", #{bra}t|Storage|#{cket})
      , (C.TypeName "at::Device", #{bra}t|Device|#{cket})
      , (C.TypeName "at::Generator", #{bra}t|Generator|#{cket})
      , (C.TypeName "std::string", #{bra}t|StdString|#{cket})
      , (C.TypeName "std::array<bool,2>", #{bra}t|StdArray CBool 2|#{cket})
      , (C.TypeName "std::array<bool,3>", #{bra}t|StdArray CBool 3|#{cket})
      , (C.TypeName "std::array<bool,4>", #{bra}t|StdArray CBool 4|#{cket})
      , (C.TypeName "std::tuple<at::Tensor,at::Tensor>", #{bra}t|(Tensor,Tensor)|#{cket})
      , (C.TypeName "std::tuple<at::Tensor,at::Tensor,at::Tensor>", #{bra}t|(Tensor,Tensor,Tensor)|#{cket})
      , (C.TypeName "std::tuple<at::Tensor,at::Tensor,at::Tensor,at::Tensor>", #{bra}t|(Tensor,Tensor,Tensor,Tensor)|#{cket})
      , (C.TypeName "std::tuple<at::Tensor,at::Tensor,at::Tensor,at::Tensor,at::Tensor>", #{bra}t|(Tensor,Tensor,Tensor,Tensor,Tensor)|#{cket})
      , (C.TypeName "std::tuple<at::Tensor,at::Tensor,at::Tensor,at::TensorList>", #{bra}t|(Tensor,Tensor,Tensor,TensorList)|#{cket})
      , (C.TypeName "std::tuple<at::Tensor,at::Tensor,double,int64_t>", #{bra}t|(Tensor,Tensor,CDouble,CLong)|#{cket})
      , (C.TypeName "std::tuple<at::Tensor,at::Tensor,float,int>", #{bra}t|(Tensor,Tensor,CFloat,CInt)|#{cket})
      , (C.TypeName "std::tuple<at::Tensor,at::Tensor,at::Tensor,int64_t>", #{bra}t|(Tensor,Tensor,Tensor,Int64)|#{cket})
      , (C.TypeName "std::vector<at::Tensor>", #{bra}t|TensorAVector|#{cket})
    ]
|]

codeTemplate :: NativeFunctionType -> [NativeFunction'] -> Text
codeTemplate typ' fns = [st|
-- generated by using spec/native_functions_modified.yaml and deps/libtorch/include/ATen/NativeFunctions.h

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

module Aten.NativeFunctions.#{package} where

import qualified Language.C.Inline.Cpp as C
import qualified Language.C.Inline.Cpp.Exceptions as C
import qualified Language.C.Inline.Context as C
import qualified Language.C.Types as C
import qualified Data.Map as Map

import Foreign.C.String
import Foreign.C.Types
import Foreign
import Aten.NativeFunctions.Type

C.context $ C.cppCtx <> mempty { C.ctxTypesTable = typeTable }

C.include "<ATen/ATen.h>"

#{renderFunctions typ' fns}
|]
  where
    package :: Text
    package =
      case typ' of
        Common -> "Common"
        Cpu -> "Dispatch.Cpu"
        Cuda -> "Dispatch.Cuda"
        SparseCpu -> "Dispatch.SparseCpu"
        SparseCuda -> "Dispatch.SparseCuda"


decodeAndCodeGen :: String -> String -> IO ()
decodeAndCodeGen basedir fileName = do
  funcs <- Y.decodeFileEither fileName :: IO (Either ParseException [NativeFunction'])
  case funcs of
    Left err' -> print err'
    Right fns -> do
      T.writeFile (basedir <> "/Aten/NativeFunctions/Type.hs") typeTemplate
      T.writeFile (basedir <> "/Aten/NativeFunctions/Common.hs") $ codeTemplate Common fns
      T.writeFile (basedir <> "/Aten/NativeFunctions/Dispatch/Cpu.hs") $ codeTemplate Cpu fns
      T.writeFile (basedir <> "/Aten/NativeFunctions/Dispatch/Cuda.hs") $ codeTemplate Cuda fns
      T.writeFile (basedir <> "/Aten/NativeFunctions/Dispatch/SparseCpu.hs") $ codeTemplate SparseCpu fns
      T.writeFile (basedir <> "/Aten/NativeFunctions/Dispatch/SparseCuda.hs") $ codeTemplate SparseCuda fns
