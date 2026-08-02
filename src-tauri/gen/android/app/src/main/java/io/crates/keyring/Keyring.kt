package io.crates.keyring

import android.content.Context

class Keyring {
  companion object {
    external fun initializeNdkContext(context: Context)
  }
}
