package org.mytonwallet.app_air.walletcore.moshi.adapter.factory

import com.squareup.moshi.JsonDataException
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class SealedJsonAdapterFactoryTest {
    private val adapter = Moshi.Builder()
        .add(SealedJsonAdapterFactory())
        .addLast(KotlinJsonAdapterFactory())
        .build()
        .adapter(TestUpdate::class.java)

    @Test
    fun returnsNullForUnknownSubtypeWhenConfigured() {
        assertNull(adapter.fromJson("""{"type":"legacy"}"""))
    }

    @Test
    fun decodesSupportedSubtype() {
        assertEquals(
            TestUpdate.Known("value"),
            adapter.fromJson("""{"type":"known","value":"value"}""")
        )
    }

    @Test
    fun rejectsMalformedSupportedSubtype() {
        assertThrows(JsonDataException::class.java) {
            adapter.fromJson("""{"type":"known"}""")
        }
    }
}

@JsonSealed("type", fallbackToNull = true)
sealed class TestUpdate {
    @JsonSealedSubtype("known")
    data class Known(val value: String) : TestUpdate()
}
