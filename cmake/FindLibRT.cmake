#[=======================================================================[.rst:
FindLibRT
-----------

Finds RT.

IMPORTED Targets
^^^^^^^^^^^^^^^^

The following :prop_tgt:`IMPORTED` targets may be defined:

``LibRT::LibRT``
	RT

``rt::rt``
	Alias for ``LibRT::LibRT``

Result variables
^^^^^^^^^^^^^^^^

This module will set the following variables in your project:

``LibRT_FOUND``
	true if RT headers and library were found
``LibRT_INCLUDE_DIR``
	the directory containing RT headers
``LibRT_LIBRARY``
	RT library to be linked (can be blank if ``LibRT_EXPLICIT_LINK`` is
	``FALSE``)
``LibRT_EXPLICIT_LINK``
	Whether RT needs to be linked to explicitly

``LibRT_INCLUDE_DIR``, ``LibRT_LIBRARY``, and ``LibRT_EXPLICIT_LINK`` are
cache variables that can be set to control the behavior of this module.

#]=======================================================================]

cmake_policy(PUSH)
cmake_minimum_required(VERSION 3.12...3.18 FATAL_ERROR)
if (POLICY CMP0125)
	# Consistent behavior for cache variables managed by find_*()
	cmake_policy(SET CMP0125 NEW)
endif()
if (POLICY CMP0132)
	# Consistent handling of compiler environment variables
	cmake_policy(SET CMP0132 NEW)
endif()

set(LibRT_INCLUDE_DIR_DOCSTR "Path to RT headers")
set(LibRT_EXPLICIT_LINK_DOCSTR "Whether RT library must be linked to be used")
set(LibRT_LIBRARY_DOCSTR "Path to the RT library (can be blank if LibRT_EXPLICIT_LINK is FALSE)")

include(FindPackageHandleStandardArgs)

find_path(LibRT_INCLUDE_DIR NAMES "time.h" DOC "${LibRT_INCLUDE_DIR_DOCSTR}")

if (LibRT_INCLUDE_DIR)

	if (DEFINED LibRT_EXPLICIT_LINK)

		if (NOT LibRT_EXPLICIT_LINK)
			set(LibRT_NO_EXPLICIT_LINK TRUE)
		endif(NOT LibRT_EXPLICIT_LINK)

	else(DEFINED LibRT_EXPLICIT_LINK)

		get_property(ENABLED_LANGUAGES GLOBAL PROPERTY ENABLED_LANGUAGES)
		if ("CXX" IN_LIST ENABLED_LANGUAGES)
			set(LibRT_TEST_SOURCE "${CMAKE_CURRENT_LIST_DIR}/librt_test.cpp")
		elseif ("C" IN_LIST ENABLED_LANGUAGES)
			set(LibRT_TEST_SOURCE "${CMAKE_CURRENT_LIST_DIR}/librt_test.c")
		else()
			message(FATAL_ERROR "Either C or CXX must be enabled.")
		endif()

		try_compile(
			LibRT_NO_EXPLICIT_LINK
			"${CMAKE_CURRENT_BINARY_DIR}"
			SOURCES "${LibRT_TEST_SOURCE}"
			CMAKE_FLAGS "-DINCLUDE_DIRECTORIES:STRING=${LibRT_INCLUDE_DIR}"
		)

	endif(DEFINED LibRT_EXPLICIT_LINK)

	if (LibRT_NO_EXPLICIT_LINK)
		set (LibRT_EXPLICIT_LINK FALSE CACHE BOOL "${LibRT_EXPLICIT_LINK_DOCSTR}")
		set(LibRT_LIBRARY "" CACHE FILEPATH "${LibRT_LIBRARY_DOCSTR}")
		find_package_handle_standard_args(LibRT REQUIRED_VARS LibRT_INCLUDE_DIR)
	else(LibRT_NO_EXPLICIT_LINK)
		set (LibRT_EXPLICIT_LINK TRUE CACHE BOOL "${LibRT_EXPLICIT_LINK_DOCSTR}")
		find_library(LibRT_LIBRARY NAMES rt DOC "${LibRT_LIBRARY_DOCSTR}")
		find_package_handle_standard_args(LibRT REQUIRED_VARS LibRT_LIBRARY LibRT_INCLUDE_DIR)
	endif(LibRT_NO_EXPLICIT_LINK)

else(LibRT_INCLUDE_DIR)

	set(LibRT_LIBRARY "LibRT_LIBRARY-NOTFOUND" CACHE FILEPATH "${LibRT_LIBRARY_DOCSTR}")
	find_package_handle_standard_args(LibRT REQUIRED_VARS LibRT_LIBRARY LibRT_INCLUDE_DIR)

endif(LibRT_INCLUDE_DIR)

if (LibRT_FOUND)
	if (NOT TARGET LibRT::LibRT)
		add_library (LibRT::LibRT INTERFACE IMPORTED)
		set_target_properties(LibRT::LibRT PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${LibRT_INCLUDE_DIR}")
		if (LibRT_EXPLICIT_LINK)
			set_target_properties(LibRT::LibRT PROPERTIES IMPORTED_LOCATION "${LibRT_LIBRARY}")
		endif(LibRT_EXPLICIT_LINK)
	endif(NOT TARGET LibRT::LibRT)
	if (NOT TARGET rt::rt)
		add_library(rt::rt ALIAS LibRT::LibRT)
	endif(NOT TARGET rt::rt)
endif(LibRT_FOUND)

cmake_policy(POP)
