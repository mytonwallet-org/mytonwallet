cmake_minimum_required(VERSION 3.4.1)

add_library(
        native-utils
        SHARED
        image.cpp
)

find_library(jnigraphics-lib jnigraphics)

target_link_libraries(
        native-utils
        ${jnigraphics-lib}
)