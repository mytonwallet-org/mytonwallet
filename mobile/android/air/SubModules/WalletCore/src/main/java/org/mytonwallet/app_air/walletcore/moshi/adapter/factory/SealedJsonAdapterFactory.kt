package org.mytonwallet.app_air.walletcore.moshi.adapter.factory

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.adapters.PolymorphicJsonAdapterFactory

@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class JsonSealed(val labelKey: String)

@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class JsonSealedSubtype(val label: String)

class SealedJsonAdapterFactory : JsonAdapter.Factory {
    override fun create(
        type: java.lang.reflect.Type,
        annotations: MutableSet<out Annotation>,
        moshi: Moshi
    ): JsonAdapter<*>? {
        val rawType = (type as? Class<*>)?.kotlin ?: return null

        val jsonSealedAnnotation =
            rawType.annotations.filterIsInstance<JsonSealed>().firstOrNull() ?: return null
        if (!rawType.isSealed) {
            throw IllegalArgumentException("Class ${rawType.simpleName} annotated with @JsonSealed must be sealed")
        }

        val labelKey = jsonSealedAnnotation.labelKey

        var polymorphicFactory =
            PolymorphicJsonAdapterFactory.of(rawType.java as Class<out Any>, labelKey)
        for (subclass in rawType.sealedSubclasses) {
            val subtypeAnnotation =
                subclass.annotations.filterIsInstance<JsonSealedSubtype>().firstOrNull()
                    ?: throw IllegalArgumentException("Subclass ${subclass.simpleName} must be annotated with @JsonSealedSubtype")

            val label = subtypeAnnotation.label

            polymorphicFactory =
                polymorphicFactory.withSubtype(subclass.java as Class<out Nothing>, label)
        }

        return polymorphicFactory.create(type, annotations, moshi)
    }
}
