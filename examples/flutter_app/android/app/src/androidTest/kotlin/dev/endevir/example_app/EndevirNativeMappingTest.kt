// M0スパイク S6: ネイティブテスト写像（CORE-109）の最小実装。
//
// ビルド時に生成されたマニフェスト（androidTest assets）からDartテストの一覧を読み、
// Parameterized JUnitで「1 Dartテスト = 1ネイティブテストケース」に写像する。
// 各ケースはアプリ内エージェント（S1）の /runTest を叩いて結果を受け取る。
// Patrolの「起動時にDart側へ階層を問い合わせる」ドライラン同期は行わない（ADR-005）。
package dev.endevir.example_app

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.BufferedReader
import java.net.Socket
import java.net.URLEncoder

@RunWith(Parameterized::class)
class EndevirNativeMappingTest(private val testName: String) {

    companion object {
        private const val AGENT_PORT = 8808

        /** マニフェスト（ビルド時静的列挙の生成物）からテストケースを作る */
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun testCases(): List<String> {
            val assets = InstrumentationRegistry.getInstrumentation().context.assets
            val json = assets.open("endevir_manifest.json").bufferedReader().readText()
            val array = JSONArray(json)
            return (0 until array.length()).map { array.getJSONObject(it).getString("fullName") }
        }

        /**
         * エージェントの死活を確認し、落ちていればアプリを起動して待つ。
         * MonitoringInstrumentation（AndroidJUnitRunner）は管理外のActivityを
         * 終了させることがあるため、テストごとに自己回復できる形にする。
         * 通常のstartActivityはAPI 29+のバックグラウンド起動制限で握り潰され
         * うるため、shell権限（uiAutomation）で起動する。
         */
        fun ensureAppRunning() {
            if (isAgentAlive()) return
            InstrumentationRegistry.getInstrumentation().uiAutomation
                .executeShellCommand(
                    "am start -n dev.endevir.example_app/.MainActivity"
                ).close()
            repeat(150) {
                if (isAgentAlive()) return
                Thread.sleep(200)
            }
            error("agent not reachable on port $AGENT_PORT")
        }

        private fun isAgentAlive(): Boolean = try {
            httpGet("/ping", timeoutMs = 2_000).contains("pong")
        } catch (_: Exception) {
            false
        }

        /**
         * 素のSocketによる最小HTTP GET。
         * instrumentationプロセスのcleartextポリシーの影響を受けない。
         */
        fun httpGet(pathWithQuery: String, timeoutMs: Int = 60_000): String {
            Socket("127.0.0.1", AGENT_PORT).use { socket ->
                socket.soTimeout = timeoutMs
                val writer = socket.getOutputStream().bufferedWriter()
                writer.write("GET $pathWithQuery HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
                writer.flush()
                val response = socket.getInputStream()
                    .bufferedReader()
                    .use(BufferedReader::readText)
                return response.substringAfter("\r\n\r\n")
            }
        }
    }

    @Test
    fun runDartTest() {
        ensureAppRunning()
        val encoded = URLEncoder.encode(testName, "UTF-8")
        val body = httpGet("/runTest?name=$encoded")
        val status = Regex("\"status\":\"(\\w+)\"").find(body)?.groupValues?.get(1)
        assertEquals("Dart test '$testName' -> $body", "passed", status)
    }
}
