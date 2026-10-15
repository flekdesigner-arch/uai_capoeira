# Project-level configuration.
cmake_minimum_required(VERSION 3.15)

# =====================================================
# FIX CMAKE NOVO + FIREBASE C++ SDK WINDOWS
# =====================================================
# Algumas versões recentes do CMake removeram compatibilidade com projetos
# que declaram cmake_minimum_required muito antigo.
#
# O Firebase C++ SDK extraído no build ainda pode usar versões antigas.
#
# Como esse arquivo fica dentro de build/ e é gerado automaticamente,
# NÃO devemos editar o arquivo gerado.
#
# Esta configuração mantém compatibilidade com o Firebase C++ SDK.
# =====================================================
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)

project(uai_capoeira LANGUAGES CXX)

# =====================================================
# FIX MSVC NOVO + PERMISSION_HANDLER_WINDOWS
# =====================================================
# Versões recentes do Visual Studio/MSVC passaram a emitir erro STL1011
# quando bibliotecas/plugins ainda usam <experimental/coroutine>.
#
# O permission_handler_windows atualmente pode depender desse header
# durante a compilação.
#
# O próprio MSVC permite manter a compatibilidade temporariamente através
# desta definição.
#
# IMPORTANTE:
# usamos add_compile_definitions GLOBALMENTE para que a definição também
# alcance os projetos CMake criados pelos plugins Flutter.
# =====================================================
add_compile_definitions(
        _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS
)

# The name of the executable created for the application.
# Change this to change the on-disk name of your application.
set(BINARY_NAME "uai_capoeira")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.15...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)

if(IS_MULTICONFIG)
  set(
          CMAKE_CONFIGURATION_TYPES
          "Debug;Profile;Release"
          CACHE STRING ""
          FORCE
  )
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(
            CMAKE_BUILD_TYPE
            "Debug"
            CACHE STRING "Flutter build mode"
            FORCE
    )

    set_property(
            CACHE CMAKE_BUILD_TYPE
            PROPERTY STRINGS
            "Debug"
            "Profile"
            "Release"
    )
  endif()
endif()

# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(
        -DUNICODE
        -D_UNICODE
)

# =====================================================
# STANDARD COMPILATION SETTINGS
# =====================================================
# Compilation settings that should be applied to most targets.
#
# Plugins Flutter normalmente utilizam esta função automaticamente.
# =====================================================
function(APPLY_STANDARD_SETTINGS TARGET)

  target_compile_features(
          ${TARGET}
          PUBLIC
          cxx_std_17
  )

  target_compile_options(
          ${TARGET}
          PRIVATE
          /W4
          /WX
          /wd"4100"
  )

  target_compile_options(
          ${TARGET}
          PRIVATE
          /EHsc
  )

  target_compile_definitions(
          ${TARGET}
          PRIVATE
          "_HAS_EXCEPTIONS=0"
  )

  target_compile_definitions(
          ${TARGET}
          PRIVATE
          "$<$<CONFIG:Debug>:_DEBUG>"
  )

endfunction()

# =====================================================
# FLUTTER
# =====================================================

# Flutter library and tool build rules.
set(
        FLUTTER_MANAGED_DIR
        "${CMAKE_CURRENT_SOURCE_DIR}/flutter"
)

add_subdirectory(
        ${FLUTTER_MANAGED_DIR}
)

# =====================================================
# APPLICATION
# =====================================================

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# =====================================================
# FLUTTER PLUGINS
# =====================================================

# Generated plugin build rules.
include(flutter/generated_plugins.cmake)

# =====================================================
# INSTALLATION
# =====================================================

# Support files are copied into place next to the executable,
# so that it can run in place.
set(
        BUILD_BUNDLE_DIR
        "$<TARGET_FILE_DIR:${BINARY_NAME}>"
)

# Make the "install" step default, as it's required to run.
set(
        CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD
        1
)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)

  set(
          CMAKE_INSTALL_PREFIX
          "${BUILD_BUNDLE_DIR}"
          CACHE PATH "..."
          FORCE
  )

endif()

set(
        INSTALL_BUNDLE_DATA_DIR
        "${CMAKE_INSTALL_PREFIX}/data"
)

set(
        INSTALL_BUNDLE_LIB_DIR
        "${CMAKE_INSTALL_PREFIX}"
)

# =====================================================
# EXECUTABLE
# =====================================================

install(
        TARGETS ${BINARY_NAME}
        RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
        COMPONENT Runtime
)

# =====================================================
# FLUTTER ICU DATA
# =====================================================

install(
        FILES "${FLUTTER_ICU_DATA_FILE}"
        DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
        COMPONENT Runtime
)

# =====================================================
# FLUTTER LIBRARY
# =====================================================

install(
        FILES "${FLUTTER_LIBRARY}"
        DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
        COMPONENT Runtime
)

# =====================================================
# PLUGIN LIBRARIES
# =====================================================

if(PLUGIN_BUNDLED_LIBRARIES)

  install(
          FILES "${PLUGIN_BUNDLED_LIBRARIES}"
          DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
          COMPONENT Runtime
  )

endif()

# =====================================================
# NATIVE ASSETS
# =====================================================

# Copy the native assets provided by build.dart from all packages.
set(
        NATIVE_ASSETS_DIR
        "${PROJECT_BUILD_DIR}native_assets/windows/"
)

install(
        DIRECTORY "${NATIVE_ASSETS_DIR}"
        DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
        COMPONENT Runtime
)

# =====================================================
# FLUTTER ASSETS
# =====================================================

# Fully re-copy the assets directory on each build to avoid stale files
# from a previous installation.
set(
        FLUTTER_ASSET_DIR_NAME
        "flutter_assets"
)

install(
        CODE "
    file(
      REMOVE_RECURSE
      \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\"
    )
  "
        COMPONENT Runtime
)

install(
        DIRECTORY
        "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
        DESTINATION
        "${INSTALL_BUNDLE_DATA_DIR}"
        COMPONENT Runtime
)

# =====================================================
# AOT LIBRARY
# =====================================================

# Install the AOT library on Profile/Release builds only.
install(
        FILES "${AOT_LIBRARY}"
        DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
        CONFIGURATIONS Profile Release
        COMPONENT Runtime
)