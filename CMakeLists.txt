cmake_minimum_required(VERSION 3.14)
project(AetherFilmOFX CXX C)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED True)

if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "Build architectures" FORCE)
endif()

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/openfx/include
    ${CMAKE_CURRENT_SOURCE_DIR}/openfx/Support/include
    ${CMAKE_CURRENT_SOURCE_DIR}
)

set(SOURCES
    main.cpp
    AetherFilmPlugin.mm
    openfx/Support/Library/ofxsImageEffect.cpp
    openfx/Support/Library/ofxsInteract.cpp
    openfx/Support/Library/ofxsLog.cpp
    openfx/Support/Library/ofxsMultiThread.cpp
    openfx/Support/Library/ofxsParams.cpp
    openfx/Support/Library/ofxsProperty.cpp
    openfx/Support/Library/ofxsPropertyValidation.cpp
    openfx/Support/Library/ofxsCore.cpp
)

# Metal Shader Compilation
if(APPLE)
    add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/AetherFilm.metallib
        COMMAND xcrun -sdk macosx metal -c -o ${CMAKE_CURRENT_BINARY_DIR}/AetherFilm.air ${CMAKE_CURRENT_SOURCE_DIR}/AetherFilm.metal
        COMMAND xcrun -sdk macosx metallib -o ${CMAKE_CURRENT_BINARY_DIR}/AetherFilm.metallib ${CMAKE_CURRENT_BINARY_DIR}/AetherFilm.air
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/AetherFilm.metal
    )
    add_custom_target(AetherFilmMetalShaders DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/AetherFilm.metallib)
endif()

add_library(${PROJECT_NAME} MODULE ${SOURCES})
if(APPLE)
    add_dependencies(${PROJECT_NAME} AetherFilmMetalShaders)
    target_link_libraries(${PROJECT_NAME} PRIVATE "-framework Foundation" "-framework Metal")
endif()

if(APPLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES
        PREFIX ""
        SUFFIX ".ofx"
        C_VISIBILITY_PRESET default
        CXX_VISIBILITY_PRESET default
        VISIBILITY_INLINES_HIDDEN 0
        LINK_FLAGS "-undefined dynamic_lookup"
    )

    set(OFX_BUNDLE_DIR "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.ofx.bundle/Contents/MacOS")
    set(OFX_PLIST_DIR  "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.ofx.bundle/Contents")
    set(OFX_RESOURCES_DIR "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.ofx.bundle/Contents/Resources")

    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${OFX_BUNDLE_DIR}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${OFX_RESOURCES_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy
            "$<TARGET_FILE:${PROJECT_NAME}>"
            "${OFX_BUNDLE_DIR}/${PROJECT_NAME}.ofx"
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
            "${OFX_PLIST_DIR}/Info.plist"
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CMAKE_CURRENT_BINARY_DIR}/AetherFilm.metallib"
            "${OFX_RESOURCES_DIR}/AetherFilm.metallib"
        COMMENT "Assembling OFX bundle"
    )

    # Auto-install to user's local directory:
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.ofx.bundle"
            "$ENV{HOME}/Library/OFX/Plugins/${PROJECT_NAME}.ofx.bundle"
        COMMENT "Installing to ~/Library/OFX/Plugins"
    )

elseif(UNIX AND NOT APPLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES PREFIX "" SUFFIX ".ofx")
elseif(WIN32)
    set_target_properties(${PROJECT_NAME} PROPERTIES PREFIX "" SUFFIX ".ofx")
endif()
