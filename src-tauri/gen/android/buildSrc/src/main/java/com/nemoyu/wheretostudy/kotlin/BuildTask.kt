import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.Properties
import org.apache.tools.ant.taskdefs.condition.Os
import org.gradle.api.Action
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.logging.LogLevel
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecSpec

open class BuildTask : DefaultTask() {
    @Input
    var rootDirRel: String? = null
    @Input
    var target: String? = null
    @Input
    var release: Boolean? = null

    @TaskAction
    fun assemble() {
        if (isTauriCliCoordinatorAvailable()) {
            runTauriCliWithFallbacks()
            return
        }

        project.logger.lifecycle(
            "Tauri CLI Android Studio bridge is unavailable; falling back to direct Cargo build for ${target ?: "unknown"}."
        )
        buildRustLibrary()
    }

    private fun runTauriCliWithFallbacks() {
        val executable = "npm"
        try {
            runTauriCli(executable)
        } catch (e: Exception) {
            if (!Os.isFamily(Os.FAMILY_WINDOWS)) {
                throw e
            }

            val fallbacks = listOf(
                "$executable.exe",
                "$executable.cmd",
                "$executable.bat",
            )

            var lastException: Exception = e
            for (fallback in fallbacks) {
                try {
                    runTauriCli(fallback)
                    return
                } catch (fallbackException: Exception) {
                    lastException = fallbackException
                }
            }

            throw lastException
        }
    }

    private fun runTauriCli(executable: String) {
        val rootDirRel = rootDirRel ?: throw GradleException("rootDirRel cannot be null")
        val target = target ?: throw GradleException("target cannot be null")
        val release = release ?: throw GradleException("release cannot be null")
        val baseArgs = listOf("run", "--", "tauri", "android", "android-studio-script")

        project.exec(Action<ExecSpec> { spec ->
            spec.workingDir(File(project.projectDir, rootDirRel))
            spec.executable = executable
            spec.args(baseArgs)
            if (project.logger.isEnabled(LogLevel.DEBUG)) {
                spec.args("-vv")
            } else if (project.logger.isEnabled(LogLevel.INFO)) {
                spec.args("-v")
            }
            if (release) {
                spec.args("--release")
            }
            spec.args("--target", target)
        }).assertNormalExitValue()
    }

    private fun isTauriCliCoordinatorAvailable(): Boolean {
        val applicationId = readApplicationId() ?: return false
        val serverAddrFile = File(System.getProperty("java.io.tmpdir"), "$applicationId-server-addr")
        if (!serverAddrFile.exists()) {
            return false
        }

        val serverAddress = serverAddrFile.readText().trim()
        val host = serverAddress.substringBefore(':', missingDelimiterValue = "")
        val port = serverAddress.substringAfter(':', missingDelimiterValue = "").toIntOrNull()
            ?: return false

        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), 1000)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun buildRustLibrary() {
        val rootDirRel = rootDirRel ?: throw GradleException("rootDirRel cannot be null")
        val target = target ?: throw GradleException("target cannot be null")
        val release = release ?: throw GradleException("release cannot be null")

        val workspaceDir = File(project.projectDir, rootDirRel).canonicalFile
        val cargoProjectDir = listOf(
            workspaceDir,
            File(workspaceDir, "src-tauri"),
        ).firstOrNull { File(it, "Cargo.toml").exists() }
            ?: throw GradleException("Unable to locate Cargo.toml from ${workspaceDir.absolutePath}")
        val cargoToml = File(cargoProjectDir, "Cargo.toml")
        val libraryName = readLibraryName(cargoToml)
        val rustTarget = resolveRustTarget(target)
        val androidPaths = resolveAndroidPaths()
        val linker = File(androidPaths.ndkToolchainBinDir, rustTarget.linkerName)
        if (!linker.exists()) {
            throw GradleException("Android linker not found: ${linker.absolutePath}")
        }

        runCargoBuild(cargoProjectDir, rustTarget, androidPaths, linker, release)

        val profileDir = if (release) "release" else "debug"
        val builtLibrary = File(
            cargoProjectDir,
            "target/${rustTarget.cargoTarget}/$profileDir/lib$libraryName.so"
        )
        if (!builtLibrary.exists()) {
            throw GradleException("Built library not found: ${builtLibrary.absolutePath}")
        }

        val jniLibsDir = File(project.projectDir, "src/main/jniLibs/${rustTarget.abi}")
        if (!jniLibsDir.exists() && !jniLibsDir.mkdirs()) {
            throw GradleException("Failed to create JNI library directory: ${jniLibsDir.absolutePath}")
        }

        builtLibrary.copyTo(File(jniLibsDir, builtLibrary.name), overwrite = true)
    }

    private fun runCargoBuild(
        cargoProjectDir: File,
        rustTarget: RustTarget,
        androidPaths: AndroidPaths,
        linker: File,
        release: Boolean,
    ) {
        val cargoExecutable = resolveCargoExecutable()
        val cargoBinDir = File(cargoExecutable).parentFile?.absolutePath
        val existingPath = System.getenv("PATH").orEmpty()
        val pathEntries = listOfNotNull(
            androidPaths.ndkToolchainBinDir.absolutePath,
            cargoBinDir,
            existingPath.takeIf { it.isNotBlank() },
        )

        project.exec(Action<ExecSpec> { spec ->
            spec.workingDir = cargoProjectDir
            spec.executable = cargoExecutable
            spec.args("build", "--target", rustTarget.cargoTarget)
            if (release) {
                spec.args("--release", "--features", "custom-protocol")
            }

            val targetEnvName = rustTarget.cargoTarget.uppercase().replace('-', '_')
            spec.environment("ANDROID_HOME", androidPaths.sdkDir.absolutePath)
            spec.environment("ANDROID_SDK_ROOT", androidPaths.sdkDir.absolutePath)
            spec.environment("ANDROID_NDK_HOME", androidPaths.ndkDir.absolutePath)
            spec.environment("NDK_HOME", androidPaths.ndkDir.absolutePath)
            spec.environment("PATH", pathEntries.joinToString(File.pathSeparator))
            spec.environment("CARGO_TARGET_${targetEnvName}_LINKER", linker.absolutePath)
        }).assertNormalExitValue()
    }

    private fun resolveCargoExecutable(): String {
        val cargoFromHome = File(System.getProperty("user.home"), ".cargo/bin/cargo")
        if (cargoFromHome.exists()) {
            return cargoFromHome.absolutePath
        }

        if (Os.isFamily(Os.FAMILY_WINDOWS)) {
            val windowsCargo = File(System.getProperty("user.home"), ".cargo/bin/cargo.exe")
            if (windowsCargo.exists()) {
                return windowsCargo.absolutePath
            }
        }

        return "cargo"
    }

    private fun resolveAndroidPaths(): AndroidPaths {
        val localProperties = Properties().apply {
            val localPropertiesFile = project.rootProject.file("local.properties")
            if (localPropertiesFile.exists()) {
                localPropertiesFile.inputStream().use(::load)
            }
        }

        val sdkDir = sequenceOf(
            localProperties.getProperty("sdk.dir")?.trim(),
            System.getenv("ANDROID_HOME")?.trim(),
            System.getenv("ANDROID_SDK_ROOT")?.trim(),
        )
            .filterNotNull()
            .map(::File)
            .firstOrNull(File::exists)
            ?: throw GradleException("Unable to locate Android SDK. Set sdk.dir in local.properties or ANDROID_HOME.")

        val ndkDir = sequenceOf(
            localProperties.getProperty("ndk.dir")?.trim(),
            System.getenv("ANDROID_NDK_HOME")?.trim(),
            System.getenv("NDK_HOME")?.trim(),
        )
            .filterNotNull()
            .map(::File)
            .firstOrNull(File::exists)
            ?: File(sdkDir, "ndk").listFiles()
                ?.filter(File::isDirectory)
                ?.sortedByDescending(File::getName)
                ?.firstOrNull()
            ?: throw GradleException("Unable to locate Android NDK under ${sdkDir.absolutePath}/ndk.")

        val prebuiltRoot = File(ndkDir, "toolchains/llvm/prebuilt")
        val ndkToolchainBinDir = prebuiltRoot.listFiles()
            ?.filter(File::isDirectory)
            ?.sortedByDescending(File::getName)
            ?.firstOrNull()
            ?.resolve("bin")
            ?.takeIf(File::exists)
            ?: throw GradleException("Unable to locate Android NDK LLVM toolchain under ${prebuiltRoot.absolutePath}.")

        return AndroidPaths(sdkDir, ndkDir, ndkToolchainBinDir)
    }

    private fun readApplicationId(): String? {
        val buildGradle = project.file("build.gradle.kts")
        if (!buildGradle.exists()) {
            return null
        }

        val content = buildGradle.readText()
        return Regex("""applicationId\\s*=\\s*\"([^\"]+)\"""")
            .find(content)
            ?.groupValues
            ?.getOrNull(1)
            ?: Regex("""namespace\\s*=\\s*\"([^\"]+)\"""")
                .find(content)
                ?.groupValues
                ?.getOrNull(1)
    }

    private fun readLibraryName(cargoToml: File): String {
        if (!cargoToml.exists()) {
            throw GradleException("Cargo.toml not found: ${cargoToml.absolutePath}")
        }

        var inLibSection = false
        for (line in cargoToml.readLines()) {
            val trimmed = line.trim()
            if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
                inLibSection = trimmed == "[lib]"
                continue
            }

            if (inLibSection && trimmed.startsWith("name")) {
                return trimmed.substringAfter('=').trim().trim('"')
            }
        }

        throw GradleException("Unable to determine Rust library name from ${cargoToml.absolutePath}")
    }

    private fun resolveRustTarget(target: String): RustTarget {
        return when (target) {
            "aarch64" -> RustTarget(
                cargoTarget = "aarch64-linux-android",
                abi = "arm64-v8a",
                linkerName = "aarch64-linux-android24-clang",
            )
            "i686" -> RustTarget(
                cargoTarget = "i686-linux-android",
                abi = "x86",
                linkerName = "i686-linux-android24-clang",
            )
            "x86_64" -> RustTarget(
                cargoTarget = "x86_64-linux-android",
                abi = "x86_64",
                linkerName = "x86_64-linux-android24-clang",
            )
            else -> throw GradleException("Unsupported Rust target: $target")
        }
    }

    private data class RustTarget(
        val cargoTarget: String,
        val abi: String,
        val linkerName: String,
    )

    private data class AndroidPaths(
        val sdkDir: File,
        val ndkDir: File,
        val ndkToolchainBinDir: File,
    )
}
