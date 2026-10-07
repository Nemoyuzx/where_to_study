package com.nemoyu.wheretostudy.nativeapp

internal class AccountIdentityRestorePolicy(initialText: String) {
    private var previousText = initialText
    private var hasEditedAccount = false

    fun onTextChanged(currentText: String, applyingLoadedIdentity: Boolean) {
        if (!applyingLoadedIdentity && currentText != previousText) hasEditedAccount = true
        previousText = currentText
    }

    // Focus is not an edit. A pristine field must receive the saved identity before Save is enabled.
    fun shouldReplaceText(
        currentText: String,
        restoredAccount: String,
        hasRestoredDraft: Boolean,
    ): Boolean = !hasEditedAccount && !hasRestoredDraft && currentText != restoredAccount
}
