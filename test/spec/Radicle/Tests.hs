{-# LANGUAGE QuasiQuotes #-}
module Radicle.Tests where

import           Protolude hiding (toList)

import           Data.List (isInfixOf, isSuffixOf)
import qualified Data.Map.Strict as Map
import           Data.Maybe (fromJust)
import           Data.String.Interpolate (i)
import           Data.String.QQ (s)
import qualified Data.Text as T
import           GHC.Exts (fromList, toList)
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck (counterexample, testProperty, (==>))

import           Radicle
import           Radicle.Internal.Arbitrary ()
import           Radicle.Internal.Core (toIdent)
import           Radicle.Internal.TestCapabilities

test_eval :: [TestTree]
test_eval =
    [ testCase "Fails for undefined atoms" $
        [s|blah|] `failsWith` UnknownIdentifier (toIdent "blah")

    , testCase "Keywords eval to themselves" $
        [s|:blah|] `succeedsWith` Keyword (toIdent "blah")

    , testCase "Succeeds for defined atoms" $ do
        let prog = [s|
              (define rocky-clark "Steve Wozniak")
              rocky-clark
              |]
        prog `succeedsWith` String "Steve Wozniak"

    , testCase "'dict' creates a Dict with given key/vals" $ do
        let prog1 = [s|(dict 'why "not")|]
        prog1 `succeedsWith` Dict (fromList [(Atom $ toIdent "why", String "not")])
        let prog2 = [s|(dict 3 1)|]
        prog2 `succeedsWith` Dict (fromList [(Number 3, Number 1)])

    , testCase "Dicts evaluate both keys are arguments" $ do
        "{(+ 1 1) (+ 1 1)}" `succeedsWith` Dict (fromList [(Number 2, Number 2)])
        "{(+ 1 1) :a (+ 0 2) :b}" `succeedsWith` Dict (fromList [(Number 2, kw "a")])

    , testCase "'cons' conses an element" $ do
        let prog = [s|(cons #t (list #f))|]
        prog `succeedsWith` List [Boolean True, Boolean False]

    , testCase "'head' returns the first element of a list" $ do
        let prog = [s|(head (list #t #f))|]
        prog `succeedsWith` Boolean True

    , testCase "'tail' returns the tail of a list" $ do
        let prog = [s|(tail (list #t #f #t))|]
        prog `succeedsWith` List [Boolean False, Boolean True]

    , testProperty "'eq?' considers equal values equal" $ \(val :: Value) -> do
        let prog = [i|(eq? #{renderPrettyDef val} #{renderPrettyDef val})|]
            res  = runTest' $ toS prog
        counterexample prog $  isLeft res || res == Right (Boolean True)

    , testCase "'eq?' works for quoted values" $ do
        let prog = [s|(eq? 'hi 'hi)|]
        prog `succeedsWith` Boolean True

    , testProperty "'eq?' considers different values different"
                $ \(v1 :: Value , v2 :: Value ) ->
                  v1 /= v2 ==> do
        -- We quote the values to prevent errors from being thrown
        let prog = [i|(eq? (quote #{renderPrettyDef v1})
                           (quote #{renderPrettyDef v2}))|]
            res  = runTest' $ toS prog
        -- Either evaluation failed or their equal.
        counterexample prog $ isLeft res || res == Right (Boolean False)

    , testCase "'member?' returns true if list contains element" $ do
        let prog = [s|(member? #t (list #f #t))|]
        prog `succeedsWith` Boolean True

    , testCase "'member?' returns false if list does not contain element" $ do
        let prog = [s|(member? "hi" (list #f #t))|]
        prog `succeedsWith` Boolean False

    , testCase "'lookup' returns value of key in map" $ do
        let prog1 = [s|(lookup 'key1 (dict 'key1 "a" 'key2 "b"))|]
        prog1 `succeedsWith` String "a"
        let prog2 = [s|(lookup 5 (dict 5 "a" 'key2 "b"))|]
        prog2 `succeedsWith` String "a"
        let prog3 = [s|(lookup '(2 3) (dict '(2 3) "a" 'key2 "b"))|]
        prog3 `succeedsWith` String "a"

    , testCase "'insert' updates the value of key in map" $ do
        let prog1 = [s|(lookup 'key1 (insert 'key1 "b" (dict 'key1 "a" 'key2 "b")))|]
        prog1 `succeedsWith` String "b"
        let prog2 = [s|(lookup 5 (insert 5 "b" (dict 5 "a" 'key2 "b")))|]
        prog2 `succeedsWith` String "b"
        let prog3 = [s|(lookup '(2 3) (insert '(2 3) "b" (dict '(2 3) "a" 'key2 "b")))|]
        prog3 `succeedsWith` String "b"

    , testCase "'insert' inserts the value of key in map" $ do
        let prog1 = [s|(lookup 'key1 (insert 'key1 "b" (dict)))|]
        prog1 `succeedsWith` String "b"
        let prog2 = [s|(lookup 5 (insert 5 "b" (dict)))|]
        prog2 `succeedsWith` String "b"
        let prog3 = [s|(lookup '(2 3) (insert '(2 3) "b" (dict)))|]
        prog3 `succeedsWith` String "b"

    , testProperty "'string-append' concatenates string" $ \ss -> do
        let args = T.unwords $ renderPrettyDef . String <$> ss
            prog = "(string-append " <> args <> ")"
            res  = runTest' prog
            expected = Right . String $ mconcat ss
            info = "Expected:\n" <> prettyEither expected <>
                   "Got:\n" <> prettyEither res
        counterexample (toS info) $ res == expected

    , testCase "'foldl' foldls the list" $ do
        let prog = [s|(foldl (lambda (x y) (- x y)) 0 (list 1 2 3))|]
        prog `succeedsWith` Number (-6)

    , testCase "'foldr' foldrs the list" $ do
        let prog = [s|(foldr (lambda (x y) (- x y)) 0 (list 1 2 3))|]
        prog `succeedsWith` Number 2

    , testCase "'map' maps over the list" $ do
        let prog = [s|(map (lambda (x) (+ x 1)) (list 1 2))|]
        prog `succeedsWith` List [Number 2, Number 3]

    , testCase "'map' (and co.) don't over-eval elements of argument list" $ do
        let prog = [s|(map (lambda (x) (cons 1 x)) (list (list 1)))
                   |]
        prog `succeedsWith` List [List [Number 1, Number 1]]

    , testCase "'eval' evaluates the list" $ do
        let prog = [s|(eval (quote #t))|]
        prog `succeedsWith` Boolean True

    , testCase "'eval' only evaluates the first quote" $ do
        let prog1 = [s|(eval (quote (quote (+ 3 2))))|]
            prog2 = [s|(quote (+ 3 2))|]
            res1 = runTest' prog1
            res2 = runTest' prog2
        res1 @?= res2

    , testProperty "'eval' does not alter functions" $ \(_v :: Value) -> do
        let prog1 = [i| (eval (lambda () #{renderPrettyDef _v})) |]
            prog2 = [i| (lambda () #{renderPrettyDef _v}) |]
            res1 = runTest' $ toS prog1
            res2 = runTest' $ toS prog2
            info = "Expected:\n" <> prettyEither res2
                <> "\nGot:\n" <> prettyEither res1
        counterexample (toS info) $ res1 == res2

    , testCase "'eval-with-env' has access to variable definitions" $ do
        let prog = [s|(head (eval-with-env
                                't
                                (dict :env (dict 'eval 'base-eval 't #t)
                                      :refs (list))))
                     |]
        prog `succeedsWith` Boolean True

    , testCase "lambdas work" $ do
        let prog = [s|((lambda (x) x) #t)|]
        prog `succeedsWith` Boolean True

    , testCase "lambda does not have access to future definitions (hyper static)" $ do
        let prog = [s|
              (define y "a")
              (define lam (lambda () y))
              (define y "b")
              (lam)
              |]
        prog `succeedsWith` String "a"

    , testCase "lambdas allow local definitions" $ do
        let prog = [s|
              ((lambda ()
                  (define y 3)
                  y))
              |]
        prog `succeedsWith` Number 3

    , testCase "lambdas throw WrongNumberOfArgs if given wrong number of args" $ do
        let prog = [s| ((lambda (x) 3)) |]
        prog `failsWith` WrongNumberOfArgs "lambda" 1 0

    , testCase "'quote' gets evaluated the right number of times" $ do
        let prog = [s|
              (define test (lambda (x) (eq? x 'hi)))
              (test 'hi)
              |]
        prog `succeedsWith` Boolean True

    , testCase "'if' works with three arguments and true cond" $ do
        let prog = [s|(if #t "a" "b")|]
        prog `succeedsWith` String "a"

    , testCase "'if' works with three arguments and false cond" $ do
        let prog = [s|(if #f "a" "b")|]
        prog `succeedsWith` String "b"

    , testCase "'if' is lazy" $ do
        let prog = [s|(if #t "a" (#t "non-sense"))|]
        prog `succeedsWith` String "a"

    , testCase "'keyword?' is true for keywords" $ do
        "(keyword? :foo)" `succeedsWith` Boolean True

    , testCase "'keyword?' is false for non keywords" $ do
        "(keyword? #t)" `succeedsWith` Boolean False

    , testCase "'do' returns the empty list if called on nothing" $ do
        "(do)" `succeedsWith` List []

    , testCase "'do' returns the result of the last argument" $ do
        "(do 1)" `succeedsWith` Number 1
        "(do 1 2 3)" `succeedsWith` Number 3

    , testCase "'do' runs effects in order" $ do
        let prog = [s|
                   (define r (ref 0))
                   (do (write-ref r 1)
                       (write-ref r 2))
                   (read-ref r)
                   |]
        prog `succeedsWith` Number 2

    , testCase "'string?' is true for strings" $ do
        let prog = [s|(string? "hi")|]
        prog `succeedsWith` Boolean True

    , testCase "'string?' is false for nonStrings" $ do
        let prog = [s|(string? #f)|]
        prog `succeedsWith` Boolean False

    , testCase "'boolean?' is true for booleans" $ do
        let prog = [s|(boolean? #t)|]
        prog `succeedsWith` Boolean True

    , testCase "'boolean?' is false for non-booleans" $ do
        let prog = [s|(boolean? "hi")|]
        prog `succeedsWith` Boolean False

    , testCase "'number?' is true for numbers" $ do
        let prog = [s|(number? 200)|]
        prog `succeedsWith` Boolean True

    , testCase "'number?' is false for non-numbers" $ do
        let prog = [s|(number? #t)|]
        prog `succeedsWith` Boolean False

    , testCase "'list?' works" $ do
        "(list? '(1 :foo ))" `succeedsWith` Boolean True
        "(list? '())" `succeedsWith` Boolean True
        "(list? :foo)" `succeedsWith` Boolean False

    , testCase "'dict?' works" $ do
        "(dict? (dict))" `succeedsWith` Boolean True
        "(dict? (dict :key 2))" `succeedsWith` Boolean True
        "(dict? :foo)" `succeedsWith` Boolean False

    , testCase "'type' returns the type, as a keyword" $ do
        let hasTy prog ty = prog `succeedsWith` Keyword (Ident ty)
        "(type :keyword)" `hasTy` "keyword"
        "(type \"string\")" `hasTy` "string"
        "(type 'a)" `hasTy` "atom"
        "(type 1)" `hasTy` "number"
        "(type #t)" `hasTy` "boolean"
        "(type list?)" `hasTy` "primop"
        "(type (list 1 2 3))" `hasTy` "list"
        "(type (dict 1 2))" `hasTy` "dict"
        "(type (ref 0))" `hasTy` "ref"
        "(type (lambda (x) x))" `hasTy` "lambda"

    , testCase "'+' sums the list of numbers" $ do
        let prog1 = [s|(+ 2 (+ 2 3))|]
        prog1 `succeedsWith` Number 7
        let prog2 = [s|(+ -1 -2 -3)|]
        prog2 `succeedsWith` Number (- 6)

    , testCase "'-' subtracts the list of numbers" $ do
        let prog1= [s|(- (+ 2 3) 1)|]
        prog1 `succeedsWith` Number 4
        let prog2 = [s|(- -1 -2 -3)|]
        prog2 `succeedsWith` Number 4

    , testCase "'*' multiplies the list of numbers" $ do
        let prog = [s|(* 2 3)|]
        prog `succeedsWith` Number 6

    , testProperty "'>' works" $ \(x, y) -> do
        let prog = [i|(> #{renderPrettyDef $ Number x} #{renderPrettyDef $ Number y})|]
            res  = runTest' $ toS prog
        counterexample prog $ res == Right (Boolean (x > y))

    , testProperty "'<' works" $ \(x, y) -> do
        let prog = [i|(< #{renderPrettyDef $ Number x} #{renderPrettyDef $ Number y})|]
            res  = runTest' $ toS prog
        counterexample prog $ res == Right (Boolean (x < y))

    , testCase "'define' fails when first arg is not an atom" $ do
        let prog = [s|(define "hi" "there")|]
        prog `failsWith` OtherError "define expects atom for first arg"

    , testCase "'catch' catches thrown exceptions" $ do
        let prog = [s|
            (catch (quote exc) (throw (quote exc) #t) (lambda (y) y))
            |]
        prog `succeedsWith` Boolean True

    , testCase "'catch' has the correct environment" $ do
        let prog = [s|
            (define t #t)
            (define f #f)
            (catch (quote exc) (throw (quote exc) f) (lambda (y) t))
            |]
        prog `succeedsWith` Boolean True

    , testCase "'catch 'any' catches any exception" $ do
        let prog = [s|
            (catch 'any (throw (quote exc) #f) (lambda (y) #t))
            |]
        prog `succeedsWith` Boolean True

    , testCase "evaluation can be redefined" $ do
        let prog = [s|
            (define eval (lambda (x) #f))
            #t
            |]
        prog `succeedsWith` Boolean False

    , testCase "'read-ref' returns the most recent value" $ do
        let prog = [s|
                (define x (ref 5))
                (write-ref x 6)
                (read-ref x)
                |]
            res = runTest' prog
        res @?= Right (Number 6)

    , testCase "mutations to refs are persisted beyond a lambda's scope" $ do
        let prog = [s|
            (define inc-ref
              (lambda (r)
                (define temp (read-ref r))
                (write-ref r (+ temp 1))
                ))
            (define a (ref 0))
            (inc-ref a)
            (read-ref a)
            |]
        let prog2 = [s|
            (define ref-mapper
              (lambda (f)
                (lambda (r)
                  (define temp (read-ref r))
                  (write-ref r (f temp)))))
            (define ref-incer (ref-mapper (lambda (x) (+ x 1))))
            (define foo (ref 0))
            (ref-incer foo)
            (read-ref foo)
            |]
        runTest' prog @?= Right (Number 1)
        runTest' prog2 @?= Right (Number 1)

    , testCase "muliple refs mutated in multiple lambdas" $ do
        let prog = [s|
            (define make-counter
              (lambda ()
                (define current (ref 0))
                (lambda ()
                  (define temp (read-ref current))
                  (write-ref current (+ temp 1))
                  temp)))
            (define c1 (make-counter))
            (c1)
            (c1)
            (define c2 (make-counter))
            (c2)
            (c1)
            (list (c1) (c2))
            |]
        runTest' prog @?= Right (List [Number 3, Number 1])

    , testProperty "read-ref . ref == id" $ \(v :: Value) -> do
        let derefed = runTest' $ toS [i|(read-ref (ref #{renderPrettyDef v}))|]
            orig    = runTest' $ toS [i|#{renderPrettyDef v}|]
            info    = "Expected:\n" <> toS (prettyEither orig)
                   <> "\nGot:\n" <> toS (prettyEither derefed)
        counterexample info $ derefed == orig

    , testCase "'show' works" $ do
        runTest' "(show 'a)" @?= Right (String "a")
        runTest' "(show ''a)" @?= Right (String "(quote a)")
        runTest' "(show \"hello\")" @?= Right (String "\"hello\"")
        runTest' "(show 42)" @?= Right (String "42.0")
        runTest' "(show #t)" @?= Right (String "#t")
        runTest' "(show #f)" @?= Right (String "#f")
        runTest' "(show (list 'a 1 \"foo\" (list 'b ''x 2 \"bar\")))" @?= Right (String "(a 1.0 \"foo\" (b (quote x) 2.0 \"bar\"))")
        runTest' "eval" @?= Right (Primop (toIdent "base-eval"))
        runTest' "(show (dict 'a 1))" @?= Right (String "{a 1.0}")
        runTest' "(show (lambda (x) x))" @?= Right (String "(lambda (x) x)")

    , testCase "'read' works" $
        runTest' "(read \"(:hello 42)\")" @?= Right (List [Keyword (toIdent "hello"), Number 42])

    , testCase "'to-json' works" $ do
        runTest' "(to-json (dict \"foo\" #t))" @?= Right (String "{\"foo\":true}")
        runTest' "(to-json (dict \"key\" (list 1 \"value\")))" @?= Right (String "{\"key\":[1,\"value\"]}")
        runTest' "(to-json (dict 1 2))" @?= Left (OtherError "Could not serialise value to JSON")
    , testCase "define-rec can define recursive functions" $ do
        let prog = [s|
            (define-rec triangular
              (lambda (n)
                (if (eq? n 0)
                    0
                    (+ n (triangular (- n 1))))))
            (triangular 10)
            |]
        runTest' prog @?= Right (Number 55)
    , testCase "define-rec errors when defining a non-function" $
        failsWith "(define-rec x 42)" (OtherError "define-rec can only be used to define functions")
    ]
  where
    failsWith src err    = runTest' src @?= Left err
    succeedsWith src val = runTest' src @?= Right val

test_parser :: [TestTree]
test_parser =
    [ testCase "parses strings" $ do
        "\"hi\"" ~~> String "hi"

    , testCase "parses booleans" $ do
        "#t" ~~> Boolean True
        "#f" ~~> Boolean False

    , testCase "parses primops" $ do
        "boolean?" ~~> Primop (toIdent "boolean?")
        "base-eval" ~~> Primop (toIdent "base-eval")

    , testCase "parses keywords" $ do
        ":foo" ~~> kw "foo"
        ":what?crazy!" ~~> kw "what?crazy!"
        ":::" ~~> kw "::"
        "::foo" ~~> kw ":foo"
        ":456" ~~> kw "456"

    , testCase "parses identifiers" $ do
        "++" ~~> Atom (toIdent "++")
        "what?crazy!" ~~> Atom (toIdent "what?crazy!")

    , testCase "parses identifiers that have a primop as prefix" $ do
        "evaluate" ~~> Atom (toIdent "evaluate")

    , testCase "parses function application" $ do
        "(++)" ~~> List [Atom (toIdent "++")]
        "(++ \"merge\" \"d\")" ~~> List [Atom (toIdent "++"), String "merge", String "d"]

    , testCase "parses numbers" $ do
        "0.15" ~~> Number 0.15
        "2000" ~~> Number 2000

    , testCase "parses identifiers" $ do
        "++" ~~> Atom (toIdent "++")
        "what?crazy!" ~~> Atom (toIdent "what?crazy!")

    , testCase "parses identifiers that have a primop as prefix" $ do
        "evaluate" ~~> Atom (toIdent "evaluate")

    , testCase "parses dicts" $ do
        "{:foo 3}" ~~> Dict (Map.singleton (Keyword (toIdent "foo")) (Number 3))

    , testCase "a dict litteral with an odd number of forms is a syntax error" $
        assertBool "succesfully parsed a dict with 3 forms" (isLeft $ parseTest "{:foo 3 4}")
    ]
  where
    x ~~> y = parseTest x @?= Right y

test_binding :: [TestTree]
test_binding =
    [ testCase "handles shadowing correctly" $ do
        [s|(((lambda (x) (lambda (x) x)) "inner") "outer")|] ~~> String "outer"
    ]
  where
    x ~~> y = runIdentity (interpret "test" x pureEnv) @?= Right y


test_pretty :: [TestTree]
test_pretty =
    [ testCase "long lists are indented" $ do
        let r = renderPretty (apl 5) (List [String "fn", String "abc"])
        r @?= "(\"fn\"\n  \"abc\")"

    , testCase "lists try to fit on one line" $ do
        let r = renderPretty (apl 80) (List [atom "fn", atom "arg1", atom "arg2"])
        r @?= "(fn arg1 arg2)"

    , testCase "dicts try to fit on one line" $ do
        let r = renderPretty (apl 80) (Dict $ Map.fromList [ (kw "k1", Number 1)
                                                           , (kw "k2", Number 2)
                                                           ])
        r @?= "{:k1 1.0 :k2 2.0}"

    , testCase "dicts split with key-val pairs" $ do
        let r = renderPretty (apl 5) (Dict $ Map.fromList [ (kw "k1", Number 1)
                                                          , (kw "k2", Number 2)
                                                          ])
        r @?= "{:k1 1.0\n :k2 2.0}"
    ]
  where
    apl cols = AvailablePerLine cols 1

test_env :: [TestTree]
test_env =
    [ testProperty "fromList . toList == identity" $ \(env' :: Env Value) ->
        fromList (toList env') == env'
    ]


test_repl_primops :: [TestTree]
test_repl_primops =
    [ testProperty "(read (get-line!)) returns the input line" read_getline_prop
    , testProperty "(read (get-line!)) regression 68450" $ 
        read_getline_prop (Atom (Ident "+7p"))

    , testCase "catch catches read-line errors" $ do
        let prog = [s|
                 (catch 'any (read-line!) (lambda (x) "caught"))
                 |]
            input = ["\"blah"]
            res = run input prog
        res @?= Right (String "caught")
    , testCase "read-file! can read a file" $ do
        let prog = "(read-file! \"foobar.rad\")"
            files = Map.singleton "foobar.rad" "foobar"
        runFiles files prog @?= Right (String "foobar")
    , testCase "load! can load definitions" $ do
        let prog = [s|
                   (load! "foo.rad")
                   (+ foo bar)
                   |]
            files = Map.singleton "foo.rad" "(define foo 42) (define bar 8)"
        runFiles files prog @?= Right (Number 50)
    ]
  where
    run stdin' prog = fst $ runTestWith replBindings stdin' prog
    runFiles :: Map Text Text -> Text -> Either (LangError Value) Value
    runFiles files prog = fst $ runTestWithFiles replBindings [] files prog

    read_getline_prop (v :: Value) = 
        let prog = [i|(eq? (read (get-line!)) (quote #{renderPrettyDef v}))|]
            res = run [renderPrettyDef v] $ toS prog
        in counterexample prog $ res == Right (Boolean True)

test_repl :: [TestTree]
test_repl =
    [ testCase "evaluates correctly" $ do
        let input = [ "((lambda (x) x) #t)" ]
            output = [ "#t" ]
        (_, result) <- runInRepl input
        result @==> output

    , testCase "handles env modifications" $ do
        let input = [ "(define id (lambda (x) x))"
                    , "(id #t)"
                    ]
            output = [ "()"
                     , "#t"
                     ]
        (_, result) <- runInRepl input
        result @==> output

    , testCase "handles 'eval' redefinition" $ do
        let input = [ "(define eval (lambda (x) #t))"
                    , "#f"
                    ]
            output = [ "()"
                     , "#t"
                     ]
        (_, result) <- runInRepl input
        result @==> output

    , testCase "(define eval (quote base-eval)) doesn't change things" $ do
        let input = [ "(define eval (quote base-eval))"
                    , "(define id (lambda (x) x))"
                    , "(id #t)"
                    ]
            output = [ "()"
                     , "()"
                     , "#t"
                     ]
        (_, result) <- runInRepl input
        result @==> output
    ]
    where
      -- In addition to the output of the lines tested, 'should-be's get
      -- printed, so we take only the last few output lines.
      r @==> out = reverse (take (length out) $ reverse r) @?= out
      -- Find repl.rad, give it all other files as possible imports, and run
      -- it.
      runInRepl inp = do
        (dir, srcs) <- sourceFiles
        srcMap <- forM srcs (\src -> (T.pack src ,) <$> readFile (dir <> src))
        let replSrc = head [ src | (name, src) <- srcMap
                                 , "repl.rad" `T.isSuffixOf` name
                                 ]
        pure $ runTestWithFiles replBindings inp (Map.fromList srcMap) (fromJust replSrc)

-- Tests all radicle files 'repl' dir. These should use the 'should-be'
-- function to ensure they are in the proper format.
test_source_files :: IO TestTree
test_source_files = testGroup "Radicle source file tests" <$> do
    (dir, files) <- sourceFiles
    let radFiles = filter (\x -> ".rad" `isSuffixOf` x && "repl." `isInfixOf` x) files
    sequence $ radFiles <&> \file -> do
        contents <- readFile (dir <> file)
        let (_, out) = runTestWith replBindings [] contents
        let makeTest line = let (name, result) = T.span (/= '\'')
                                               $ T.drop 1
                                               $ T.dropWhile (/= '\'') line
                            in testCase (toS name) $ result @?= "' succeeded\""
        pure $ testGroup file
            $ [ makeTest ln | ln <- out, "\"Test" `T.isPrefixOf` ln ]

-- * Utils

kw :: Text -> Value
kw = Keyword . toIdent

atom :: Text -> Value
atom = Atom . toIdent

-- -- | Like 'parse', but uses "(test)" as the source name and the default set of
-- -- primops.
parseTest :: MonadError Text m => Text -> m Value
parseTest t = parse "(test)" t (Map.keys $ bindingsPrimops e)
  where
    e :: Bindings (Lang Identity)
    e = pureEnv

prettyEither :: Either (LangError Value) Value -> T.Text
prettyEither (Left e)  = "Error: " <> renderPrettyDef e
prettyEither (Right v) = renderPrettyDef v
