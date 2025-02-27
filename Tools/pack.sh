#!/bin/bash

export PATH=~/miniconda/bin:/opt/homebrew/bin:/opt/MonkeyDev/bin:$MonkeyDevTheosPath/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH

MONKEYDEV_PATH="/opt/MonkeyDev"

# temp path
TEMP_PATH="${SRCROOT}/${TARGET_NAME}/tmp"

# monkeyparser
MONKEYPARSER="${MONKEYDEV_PATH}/bin/monkeyparser"

# insert_dylib
INSERT_DYLIB="${MONKEYDEV_PATH}/bin/insert_dylib"

# optool
OPTOOL="${MONKEYDEV_PATH}/bin/optool"

# create ipa script
CREATE_IPA="${MONKEYDEV_PATH}/bin/createIPA.command"

# build app path
BUILD_APP_PATH="${BUILT_PRODUCTS_DIR}/${TARGET_NAME}.app"

# default demo app
DEMOTARGET_APP_PATH="${MONKEYDEV_PATH}/Resource/TargetApp.app"

# link framework path
FRAMEWORKS_TO_INJECT_PATH="${MONKEYDEV_PATH}/Frameworks/"

# target app placed
TARGET_APP_PUT_PATH="${SRCROOT}/${TARGET_NAME}/TargetApp"

# Compatiable old version
MONKEYDEV_INSERT_DYLIB=${MONKEYDEV_INSERT_DYLIB:=YES}
MONKEYDEV_TARGET_APP=${MONKEYDEV_TARGET_APP:=Optional}
MONKEYDEV_ADD_SUBSTRATE=${MONKEYDEV_ADD_SUBSTRATE:=YES}
MONKEYDEV_DEFAULT_BUNDLEID=${MONKEYDEV_DEFAULT_BUNDLEID:=NO}

#默认SSH设备IP
export DefaultDeviceIP="localhost"
#默认SSH端口号
export DefaultDevicePort="2222"
#默认SSH用户名
export DefaultDeviceUser="root"
#默认SSH密码
export DefaultDevicePassword="alpine"
#默认SSH证书
export DefaultDeviceIdentityFile=""
#默认Frida host
export DefaultDeviceFridaHost="localhost:27042"

export userName="${SUDO_USER-$USER}"
export userGroup=`id -g $userName`
export userHome=`eval echo ~$userName`
export bashProfileFiles=("$userHome/.zshrc" "$userHome/.bash_profile" "$userHome/.bashrc" "$userHome/.bash_login" "$userHome/.profile")

function isRelease() {
	if [[ "${CONFIGURATION}" = "Release" ]]; then
		true
	else
		false
	fi
}

function panic() { # args: exitCode, message...
	local exitCode=$1
	set +e
	
	shift
	[[ "$@" == "" ]] || \
		echo "$@" >&2

	exit ${exitCode}
}

function determineBashProfileFile()
{
	local f
	local filePath
	
	for f in "${bashProfileFiles[@]}"; do
		if [[ -f "$f" ]]; then
            if [[ -n `perl -ne 'print $1 if /^(?:export)? *'"MonkeyDevPath"'=(.*)$/' "$f"` ]]; then
    			filePath="$f"
    			break
            fi
		fi
	done
	
	if [[ $filePath == "" ]]; then

		filePath="$bashProfileFiles" # use first array item
		
		touch "$filePath" || \
			panic $? "Failed to touch $filePath"
			
		changeOwn "$userName:$userGroup" "$filePath"
		changeMode 0600 "$filePath"
	fi
	
	# return #
	echo "$filePath"
}

function getBashProfileEnvVarValue() # args: envVarName
{
	local envVarName="$1"
	local perlValue
	local bashProfileFile
	
	bashProfileFile=`determineBashProfileFile`
	
	perlValue=`perl -ne 'print $1 if /^(?:export)? *'"$envVarName"'=(.*)$/' "$bashProfileFile"` || \
		panic $? "Failed to perl"
	
	# return #
	echo "$perlValue"
}

function requireExportedVariable() # args: envVarName[, message]
{
	local envVarName="$1"
	local message="$2"
	local value
	
	if [[ ${!envVarName} == "" ]]; then
		value=`getBashProfileEnvVarValue "$envVarName"`
	
		[[ $value != "" ]] || \
			panic 1 "Environment variable $envVarName is not set or is empty"

		eval $envVarName='$value'
		export $envVarName
	fi
}

function checkApp(){
	local TARGET_APP_PATH="$1"

	# remove Plugin an Watch
	rm -rf "${TARGET_APP_PATH}/PlugIns" || true
	rm -rf "${TARGET_APP_PATH}/Watch" || true

	/usr/libexec/PlistBuddy -c 'Delete UISupportedDevices' "${TARGET_APP_PATH}/Info.plist" 2>/dev/null

	VERIFY_RESULT=`export MONKEYDEV_CLASS_DUMP=${MONKEYDEV_CLASS_DUMP};MONKEYDEV_RESTORE_SYMBOL=${MONKEYDEV_RESTORE_SYMBOL};"$MONKEYPARSER" verify -t "${TARGET_APP_PATH}" -o "${SRCROOT}/${TARGET_NAME}"`

	if [[ $? -eq 16 ]]; then
	  	panic 1 "${VERIFY_RESULT}"
	else
	  	echo "${VERIFY_RESULT}"
	fi
}

function pack(){
	TARGET_INFO_PLIST=${SRCROOT}/${TARGET_NAME}/Info.plist
	# environment
	CURRENT_EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "${TARGET_INFO_PLIST}" 2>/dev/null)

	# create tmp dir
	rm -rf "${TEMP_PATH}" || true
	mkdir -p "${TEMP_PATH}" || true

	# latestbuild
	ln -fhs "${BUILT_PRODUCTS_DIR}" "${PROJECT_DIR}"/LatestBuild
	cp -rf "${CREATE_IPA}" "${PROJECT_DIR}"/LatestBuild/

	# deal ipa or app
	TARGET_APP_PATH=$(find "${SRCROOT}/${TARGET_NAME}" -type d | grep "\.app$" | head -n 1)
	TARGET_IPA_PATH=$(find "${SRCROOT}/${TARGET_NAME}" -type f | grep "\.ipa$" | head -n 1)

	if [[ ${TARGET_APP_PATH} ]]; then
		cp -rf "${TARGET_APP_PATH}" "${TARGET_APP_PUT_PATH}"
	fi

	if [[ ! ${TARGET_APP_PATH} ]] && [[ ! ${TARGET_IPA_PATH} ]] && [[ ${MONKEYDEV_TARGET_APP} != "Optional" ]]; then
		echo "pulling decrypted ipa from jailbreak device......."

		#如果编译设置里面MonkeyDevDeviceIP为空的话，就从用户的profile里面去拿，否则使用默认值
		[[ $MonkeyDevDeviceIP != "" ]] || \
			MonkeyDevDeviceIP=`getBashProfileEnvVarValue "MonkeyDevDeviceIP"`
		[[ $MonkeyDevDeviceIP != "" ]] || \
			MonkeyDevDeviceIP="$DefaultDeviceIP"

		#如果编译设置里面MonkeyDevDevicePort为空的话，就从用户的profile里面去拿，否则使用默认值
		[[ $MonkeyDevDevicePort != "" ]] || \
			MonkeyDevDevicePort=`getBashProfileEnvVarValue "MonkeyDevDevicePort"`
		[[ $MonkeyDevDevicePort != "" ]] || \
			MonkeyDevDevicePort="$DefaultDevicePort"

		#如果编译设置里面MonkeyDevDeviceUser为空的话，就从用户的profile里面去拿，否则使用默认值
		[[ $MonkeyDevDeviceUser != "" ]] || \
			MonkeyDevDeviceUser=`getBashProfileEnvVarValue "MonkeyDevDeviceUser"`
		[[ $MonkeyDevDeviceUser != "" ]] || \
			MonkeyDevDeviceUser="$DefaultDeviceUser"

		#如果编译设置里面MonkeyDevDevicePassword为空的话，就从用户的profile里面去拿，否则使用默认值
		[[ $MonkeyDevDevicePassword != "" ]] || \
			MonkeyDevDevicePassword=`getBashProfileEnvVarValue "MonkeyDevDevicePassword"`
		[[ $MonkeyDevDevicePassword != "" ]] || \
			MonkeyDevDevicePassword="$DefaultDevicePassword"

		#如果编译设置里面MonkeyDevDeviceIdentityFile为空的话，就从用户的profile里面去拿，否则使用默认值
		[[ $MonkeyDevDeviceIdentityFile != "" ]] || \
			MonkeyDevDeviceIdentityFile=`getBashProfileEnvVarValue "MonkeyDevDeviceIdentityFile"`
		[[ $MonkeyDevDeviceIdentityFile != "" ]] || \
			MonkeyDevDeviceIdentityFile="$DefaultDeviceIdentityFile"

		#如果编译设置里面MonkeyDevDeviceFridaHost为空的话，就从用户的profile里面去拿，否则使用默认值
		[[ $MonkeyDevDeviceFridaHost != "" ]] || \
			MonkeyDevDeviceFridaHost=`getBashProfileEnvVarValue "MonkeyDevDeviceFridaHost"`
		[[ $MonkeyDevDeviceFridaHost != "" ]] || \
			MonkeyDevDeviceFridaHost="$DefaultDeviceFridaHost"

		echo "${MONKEYDEV_PATH}/bin/dump.py ${MONKEYDEV_TARGET_APP} -o "${TARGET_APP_PUT_PATH}/TargetApp.ipa" --host ${MonkeyDevDeviceIP} --port ${MonkeyDevDevicePort} --user ${MonkeyDevDeviceUser} --password ${MonkeyDevDevicePassword} --key_filename ${MonkeyDevDeviceIdentityFile} --remote ${MonkeyDevDeviceFridaHost}"

		PYTHONIOENCODING=utf-8 ${MONKEYDEV_PATH}/bin/dump.py ${MONKEYDEV_TARGET_APP} -o "${TARGET_APP_PUT_PATH}/TargetApp.ipa" --host ${MonkeyDevDeviceIP} --port ${MonkeyDevDevicePort} --user ${MonkeyDevDeviceUser} --password ${MonkeyDevDevicePassword} --key_filename ${MonkeyDevDeviceIdentityFile} --remote ${MonkeyDevDeviceFridaHost} || panic 1 "dump.py error"
		TARGET_IPA_PATH=$(find "${TARGET_APP_PUT_PATH}" -type f | grep "\.ipa$" | head -n 1)
	fi

	if [[ ! ${TARGET_APP_PATH} ]] && [[ ${TARGET_IPA_PATH} ]]; then
		unzip -oqq "${TARGET_IPA_PATH}" -d "${TEMP_PATH}"
		cp -rf "${TEMP_PATH}/Payload/"*.app "${TARGET_APP_PUT_PATH}"
	fi
	
	if [ -f "${BUILD_APP_PATH}/embedded.mobileprovision" ]; then
		mv "${BUILD_APP_PATH}/embedded.mobileprovision" "${BUILD_APP_PATH}"/..
	fi

	TARGET_APP_PATH=$(find "${TARGET_APP_PUT_PATH}" -type d | grep "\.app$" | head -n 1)

	if [[ -f "${TARGET_APP_PUT_PATH}"/.current_put_app ]]; then
		if [[ $(cat ${TARGET_APP_PUT_PATH}/.current_put_app) !=  "${TARGET_APP_PATH}" ]]; then
			rm -rf "${BUILD_APP_PATH}" || true
		 	mkdir -p "${BUILD_APP_PATH}" || true
		 	rm -rf "${TARGET_APP_PUT_PATH}"/.current_put_app
			echo "${TARGET_APP_PATH}" >> "${TARGET_APP_PUT_PATH}"/.current_put_app
		fi
	fi

	COPY_APP_PATH=${TARGET_APP_PATH}

	if [[ "${TARGET_APP_PATH}" = "" ]]; then
		COPY_APP_PATH=${DEMOTARGET_APP_PATH}
		cp -rf "${COPY_APP_PATH}/" "${BUILD_APP_PATH}/"
		checkApp "${BUILD_APP_PATH}"
	else
		checkApp "${COPY_APP_PATH}"
		cp -rf "${COPY_APP_PATH}/" "${BUILD_APP_PATH}/"
	fi

	if [ -f "${BUILD_APP_PATH}/../embedded.mobileprovision" ]; then
		mv "${BUILD_APP_PATH}/../embedded.mobileprovision" "${BUILD_APP_PATH}"
	fi

	# get target info
	ORIGIN_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier"  "${COPY_APP_PATH}/Info.plist" 2>/dev/null)
	TARGET_EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable"  "${COPY_APP_PATH}/Info.plist" 2>/dev/null)

	if [[ ${CURRENT_EXECUTABLE} != ${TARGET_EXECUTABLE} ]]; then
		cp -rf "${COPY_APP_PATH}/Info.plist" "${TARGET_INFO_PLIST}"
	fi

	TARGET_DISPLAY_NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleDisplayName" "${TARGET_INFO_PLIST}" 2>/dev/null)

	# copy default framewrok
	TARGET_APP_FRAMEWORKS_PATH="${BUILD_APP_PATH}/Frameworks/"

	if [ ! -d "${TARGET_APP_FRAMEWORKS_PATH}" ]; then
		mkdir -p "${TARGET_APP_FRAMEWORKS_PATH}"
	fi

	if [[ ${MONKEYDEV_INSERT_DYLIB} == "YES" ]];then
		cp -rf "${BUILT_PRODUCTS_DIR}/lib""${TARGET_NAME}""Dylib.dylib" "${TARGET_APP_FRAMEWORKS_PATH}"
		cp -rf "${FRAMEWORKS_TO_INJECT_PATH}" "${TARGET_APP_FRAMEWORKS_PATH}"
		if [[ ${MONKEYDEV_ADD_SUBSTRATE} != "YES" ]];then
			rm -rf "${TARGET_APP_FRAMEWORKS_PATH}/libsubstrate.dylib"
		fi
		if isRelease; then
            rm -rf "${TARGET_APP_FRAMEWORKS_PATH}"/RevealServer.framework
            rm -rf "${TARGET_APP_FRAMEWORKS_PATH}"/LookinServer.framework
			rm -rf "${TARGET_APP_FRAMEWORKS_PATH}"/libcycript*
		fi
	fi

	if [[ -d "$SRCROOT/${TARGET_NAME}/Resources" ]]; then
	 for file in "$SRCROOT/${TARGET_NAME}/Resources"/*; do
	 	extension="${file#*.}"
	  	filename="${file##*/}"
	  	if [[ "$extension" == "storyboard" ]]; then
	  		ibtool --compile "${BUILD_APP_PATH}/$filename"c "$file"
	  	else
	  		cp -rf "$file" "${BUILD_APP_PATH}/"
	  	fi
	 done
	fi

	# Inject the Dynamic Lib
	APP_BINARY=`plutil -convert xml1 -o - ${BUILD_APP_PATH}/Info.plist | grep -A1 Exec | tail -n1 | cut -f2 -d\> | cut -f1 -d\<`

	if [[ ${MONKEYDEV_INSERT_DYLIB} == "YES" ]];then
		if [[ ${MONKEYDEV_INSERT_DYLIB_TOOLS} == "INSERT_DYLIB" ]];then
			"$INSERT_DYLIB" --inplace --overwrite --all-yes "@executable_path/Frameworks/lib${TARGET_NAME}Dylib.dylib" "${BUILD_APP_PATH}/${APP_BINARY}"
		elif [[ ${MONKEYDEV_INSERT_DYLIB_TOOLS} == "OPTOOL" ]]; then
			"$OPTOOL" install -c load -p "@executable_path/Frameworks/lib${TARGET_NAME}Dylib.dylib" -t "${BUILD_APP_PATH}/${APP_BINARY}"
		else
			"$MONKEYPARSER" install -c load -p "@executable_path/Frameworks/lib${TARGET_NAME}Dylib.dylib" -t "${BUILD_APP_PATH}/${APP_BINARY}"
		fi

		if [[ ${MONKEYDEV_INSERT_DYLIB_TOOLS} == "OPTOOL" ]];then
			# "$OPTOOL" uninstall -p "@executable_path/Frameworks/lib${TARGET_NAME}Dylib.dylib" -t "${BUILD_APP_PATH}/${APP_BINARY}"
			"$OPTOOL" unrestrict -w -t "${BUILD_APP_PATH}/${APP_BINARY}"
		else
			"$MONKEYPARSER" unrestrict -t "${BUILD_APP_PATH}/${APP_BINARY}"
		fi
		
		chmod +x "${BUILD_APP_PATH}/${APP_BINARY}"
	fi

	# Update Info.plist for Target App
	if [[ "${TARGET_DISPLAY_NAME}" != "" ]]; then
		for file in `ls "${BUILD_APP_PATH}"`;
		do
			extension="${file#*.}"
		    if [[ -d "${BUILD_APP_PATH}/$file" ]]; then
				if [[ "${extension}" == "lproj" ]]; then
					if [[ -f "${BUILD_APP_PATH}/${file}/InfoPlist.strings" ]];then
						/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${TARGET_DISPLAY_NAME}" "${BUILD_APP_PATH}/${file}/InfoPlist.strings"
					fi
		    	fi
			fi
		done
	fi

	if [[ ${MONKEYDEV_DEFAULT_BUNDLEID} = NO ]];then 
		/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${PRODUCT_BUNDLE_IDENTIFIER}" "${TARGET_INFO_PLIST}"
	else
		/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${ORIGIN_BUNDLE_ID}" "${TARGET_INFO_PLIST}"
	fi

	/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFiles" "${TARGET_INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles array" "${TARGET_INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles: string ${TARGET_NAME}/icon.png" "${TARGET_INFO_PLIST}"

	cp -rf "${TARGET_INFO_PLIST}" "${BUILD_APP_PATH}/Info.plist"

	#cocoapods
	if [[ -f "${SRCROOT}/Pods/Target Support Files/Pods-""${TARGET_NAME}""Dylib/Pods-""${TARGET_NAME}""Dylib-frameworks.sh" ]]; then
		source "${SRCROOT}/Pods/Target Support Files/Pods-""${TARGET_NAME}""Dylib/Pods-""${TARGET_NAME}""Dylib-frameworks.sh"
	fi

	if [[ -f "${SRCROOT}/Pods/Target Support Files/Pods-""${TARGET_NAME}""Dylib/Pods-""${TARGET_NAME}""Dylib-resources.sh" ]]; then
		source "${SRCROOT}/Pods/Target Support Files/Pods-""${TARGET_NAME}""Dylib/Pods-""${TARGET_NAME}""Dylib-resources.sh"
	fi

	if [[ -f "${SRCROOT}/../Pods/Target Support Files/Pods-""${TARGET_NAME}""Dylib/Pods-""${TARGET_NAME}""Dylib-frameworks.sh" ]]; then
		source "${SRCROOT}/../Pods/Target Support Files/Pods-""${TARGET_NAME}""Dylib/Pods-""${TARGET_NAME}""Dylib-frameworks.sh"
	fi

	if [[ -f "${SRCROOT}/../Pods/Target Support Files/Pods-""${TARGET_NAME}""Dylib/Pods-""${TARGET_NAME}""Dylib-resources.sh" ]]; then
		source "${SRCROOT}/../Pods/Target Support Files/Pods-""${TARGET_NAME}""Dylib/Pods-""${TARGET_NAME}""Dylib-resources.sh"
	fi
}

if [[ "$1" == "codesign" ]]; then
	${MONKEYPARSER} codesign -i "${EXPANDED_CODE_SIGN_IDENTITY}" -t "${BUILD_APP_PATH}"
	if [[ ${MONKEYDEV_INSERT_DYLIB} == "NO" ]];then
		rm -rf "${BUILD_APP_PATH}/Frameworks/lib${TARGET_NAME}Dylib.dylib"
	fi
else
	pack
fi
