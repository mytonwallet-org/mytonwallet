package org.mytonwallet.app_air.uicomponents.image.svg

import com.facebook.imageformat.ImageFormat

object SvgImageFormat {
    val SVG = ImageFormat("SVG_FORMAT", "svg")

    private val HEADER_TAGS = listOf("<svg", "<?xml")
    private const val HEADER_LENGTH = 64

    val formatChecker = object : ImageFormat.FormatChecker {
        override val headerSize = HEADER_LENGTH

        override fun determineFormat(headerBytes: ByteArray, headerSize: Int): ImageFormat {
            if (headerSize < 2) return ImageFormat.UNKNOWN
            val header = String(
                headerBytes,
                0,
                minOf(headerSize, HEADER_LENGTH),
                Charsets.UTF_8
            ).trimStart('﻿', ' ', '\n', '\r', '\t').lowercase()
            return if (HEADER_TAGS.any { header.startsWith(it) }) SVG else ImageFormat.UNKNOWN
        }
    }
}