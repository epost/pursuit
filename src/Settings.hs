-- | Settings are centralized, as much as possible, into this file. This
-- includes database connection settings, static file locations, etc.
-- In addition, you can configure a number of different aspects of Yesod
-- by overriding methods in the Yesod typeclass. That instance is
-- declared in the Foundation.hs file.
module Settings where

import ClassyPrelude.Yesod
import Control.Exception           (throw)
import Data.Aeson                  (Result (..), fromJSON, withObject, (.!=),
                                    (.:?))
import Data.FileEmbed              (embedFile)
import Data.Yaml                   (decodeEither')
import Language.Haskell.TH.Syntax  (Exp, Name, Q)
import Network.Wai.Handler.Warp    (HostPreference)
import Yesod.Default.Config2       (applyEnvValue, configSettingsYml)
import Yesod.Default.Util          (WidgetFileSettings, widgetFileNoReload,
                                    widgetFileReload)

newtype GithubAuthToken =
  GithubAuthToken { runGithubAuthToken :: ByteString }
  deriving (Show, Eq, Ord)

-- | Runtime settings to configure this application. These settings can be
-- loaded from various sources: defaults, environment variables, config files,
-- theoretically even a database.
data AppSettings = AppSettings
    { appStaticDir              :: String
    -- ^ Directory from which to serve static files.
    , appRoot                   :: Text
    -- ^ Base for all generated URLs.
    , appHost                   :: HostPreference
    -- ^ Host/interface the server should bind to.
    , appPort                   :: Int
    -- ^ Port to listen on
    , appIpFromHeader           :: Bool
    -- ^ Get the IP address from the header when logging. Useful when sitting
    -- behind a reverse proxy.

    , appDetailedRequestLogging :: Bool
    -- ^ Use detailed request logging system
    , appShouldLogAll           :: Bool
    -- ^ Should all log messages be displayed?
    , appReloadTemplates        :: Bool
    -- ^ Use the reload version of templates
    , appMutableStatic          :: Bool
    -- ^ Assume that files in the static dir may change after compilation
    , appSkipCombining          :: Bool
    -- ^ Perform no stylesheet/script combining

    -- Example app-specific configuration values.
    , appAnalytics              :: Maybe Text
    -- ^ Google Analytics code
    , appGithubAuthToken        :: Maybe GithubAuthToken
    -- ^ Github OAuth token (for fetching READMEs).
    , appDataDir                :: String
    -- ^ Directory where package data is kept.
    , appGithubClientID         :: ByteString
    -- ^ GitHub OAuth client ID
    , appGithubClientSecret         :: ByteString
    -- ^ GitHub OAuth client secret
    }

instance FromJSON AppSettings where
    parseJSON = withObject "AppSettings" $ \o -> do
        let defaultDev =
#if DEVELOPMENT
                True
#else
                False
#endif
        appStaticDir              <- o .: "static-dir"
        appRoot                   <- o .: "approot"
        appHost                   <- fromString <$> o .: "host"
        appPort                   <- o .: "port"
        appIpFromHeader           <- o .: "ip-from-header"

        appDetailedRequestLogging <- o .:? "detailed-logging" .!= defaultDev
        appShouldLogAll           <- o .:? "should-log-all"   .!= defaultDev
        appReloadTemplates        <- o .:? "reload-templates" .!= defaultDev
        appMutableStatic          <- o .:? "mutable-static"   .!= defaultDev
        appSkipCombining          <- o .:? "skip-combining"   .!= defaultDev

        appAnalytics              <- o .:? "analytics"

        appDataDir <- o .: "data-dir"

#if DEVELOPMENT
        let appGithubAuthToken    = Nothing
        let appGithubClientID     = "618b30c313f09b9ca795"
        let appGithubClientSecret = "053aaf80116894788ac38f7e2f8d8828fa007969"
#else
        let enc = encodeUtf8 :: Text -> ByteString
        appGithubAuthToken    <- map (map (GithubAuthToken . enc)) $ o .: "github-auth-token"
        appGithubClientID     <- map enc $ o .: "github-client-id"
        appGithubClientSecret <- map enc $ o .: "github-client-secret"
#endif

        return AppSettings {..}

-- | Settings for 'widgetFile', such as which template languages to support and
-- default Hamlet settings.
--
-- For more information on modifying behavior, see:
--
-- https://github.com/yesodweb/yesod/wiki/Overriding-widgetFile
widgetFileSettings :: WidgetFileSettings
widgetFileSettings = def

-- | How static files should be combined.
combineSettings :: CombineSettings
combineSettings = def

-- The rest of this file contains settings which rarely need changing by a
-- user.

widgetFile :: String -> Q Exp
widgetFile = (if appReloadTemplates compileTimeAppSettings
                then widgetFileReload
                else widgetFileNoReload)
              widgetFileSettings

-- | Raw bytes at compile time of @config/settings.yml@
configSettingsYmlBS :: ByteString
configSettingsYmlBS = $(embedFile configSettingsYml)

-- | @config/settings.yml@, parsed to a @Value@.
configSettingsYmlValue :: Value
configSettingsYmlValue = either throw id $ decodeEither' configSettingsYmlBS

-- | A version of @AppSettings@ parsed at compile time from @config/settings.yml@.
compileTimeAppSettings :: AppSettings
compileTimeAppSettings =
    case fromJSON $ applyEnvValue False mempty configSettingsYmlValue of
        Error e -> error e
        Success settings -> settings

-- The following two functions can be used to combine multiple CSS or JS files
-- at compile time to decrease the number of http requests.
-- Sample usage (inside a Widget):
--
-- > $(combineStylesheets 'StaticR [style1_css, style2_css])

combineStylesheets :: Name -> [Route Static] -> Q Exp
combineStylesheets = combineStylesheets'
    (appSkipCombining compileTimeAppSettings)
    combineSettings

combineScripts :: Name -> [Route Static] -> Q Exp
combineScripts = combineScripts'
    (appSkipCombining compileTimeAppSettings)
    combineSettings
