{-# LANGUAGE OverloadedStrings #-}

module Smos.Actions.File
  ( saveFile,
    saveCurrentSmosFile,
    closeCurrentFile,
    switchToFile,
    switchToCursor,
  )
where

import Control.Monad.Trans.Resource
import Path
import Smos.Actions.Utils
import Smos.Cursor.SmosFileEditor
import Smos.Types

saveFile :: Action
saveFile =
  Action
    { actionName = "saveFile",
      actionFunc = saveCurrentSmosFile,
      actionDescription = "Save the current file"
    }

saveCurrentSmosFile :: SmosM ()
saveCurrentSmosFile = modifyMSmosFileEditorCursorMS $ mapM $ liftIO . smosFileEditorCursorSave

switchToFile :: Path Abs File -> SmosM ()
switchToFile path = modifyEditorCursorS $ \ec -> do
  if (smosFileEditorPath <$> editorCursorFileCursor ec) == Just path
    then pure ec {editorCursorSelection = FileSelected} -- Just don't change anything
    else do
      mErrOrSmec <- startSmosFileEditorCursor path
      case mErrOrSmec of
        Nothing -> do
          addErrorMessage "Unable to get a lock on the file to switch to"
          pure ec -- Couldn't get a lock, do nothing
        Just errOrSmec ->
          case errOrSmec of
            Left _ -> do
              addErrorMessage "The file to switch to is not a valid smos file"
              pure ec -- Do nothing if the file is not a smos file
            Right smec -> do
              saveCurrentSmosFile
              closeCurrentFile
              pure $
                ec
                  { editorCursorLastOpenedFile = Just path,
                    editorCursorSelection = FileSelected,
                    editorCursorFileCursor = Just smec
                  }

switchToCursor :: Path Abs File -> Maybe SmosFileCursor -> SmosM ()
switchToCursor path msfc = modifyEditorCursorS $ \ec -> do
  case editorCursorFileCursor ec of
    Nothing -> doSwitchEntirely ec
    Just sfec ->
      if smosFileEditorPath sfec == path
        then do
          -- Don't close this file and open the same, but keep the same one open and just change the cursor.
          pure
            ec
              { editorCursorFileCursor = Just $ resetSmosFileEditorCursor msfc sfec,
                editorCursorSelection = FileSelected
              }
        else doSwitchEntirely ec
  where
    doSwitchEntirely ec = do
      saveCurrentSmosFile
      closeCurrentFile
      mSmec <- startSmosFileEditorCursorWithCursor path msfc
      case mSmec of
        Nothing -> do
          addErrorMessage "Unable to get a lock on the file to switch to"
          pure ec -- Couldn't get a lock, do nothing
        Just smec -> do
          pure $
            ec
              { editorCursorLastOpenedFile = Just path,
                editorCursorSelection = FileSelected,
                editorCursorFileCursor = Just smec
              }

-- Note that this leaves the file cursor invalidated, so it must not end up in the editor cursor sum after this.
closeCurrentFile :: SmosM ()
closeCurrentFile = modifySmosFileEditorCursorS $ \sfec -> do
  liftResourceT (smosFileEditorCursorClose sfec)
  pure sfec
