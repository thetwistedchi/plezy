//! JNI entry points for the Android app's browser
//! (android/.../browser/AdblockEngine.kt). Thin wrappers around the C
//! interface in lib.rs, so both platforms run the same code.

use std::ffi::{c_char, c_int, CStr, CString};

use jni::objects::{JClass, JString};
use jni::sys::{jlong, jstring};
use jni::JNIEnv;

use crate::{
    plezy_adblock_check, plezy_adblock_free, plezy_adblock_free_string, plezy_adblock_generic_script,
    plezy_adblock_load, plezy_adblock_page_script, PlezyAdblock,
};

fn read(env: &mut JNIEnv, text: &JString) -> Option<CString> {
    if text.is_null() {
        return None;
    }
    let value: String = env.get_string(text).ok()?.into();
    CString::new(value.replace('\0', "")).ok()
}

/// Takes a string returned by the C interface and frees it.
fn take(ptr: *mut c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let text = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned();
    plezy_adblock_free_string(ptr);
    Some(text)
}

fn java(env: &mut JNIEnv, text: Option<String>) -> jstring {
    match text {
        Some(t) => env.new_string(t).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_edde746_plezy_browser_AdblockEngine_load(
    mut env: JNIEnv,
    _class: JClass,
    config: JString,
) -> jlong {
    match read(&mut env, &config) {
        Some(c) => plezy_adblock_load(c.as_ptr()) as jlong,
        None => 0,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_edde746_plezy_browser_AdblockEngine_free(_env: JNIEnv, _class: JClass, engine: jlong) {
    plezy_adblock_free(engine as *mut PlezyAdblock);
}

/// null = allow, "" = block, anything else = the data: URL to answer with.
#[no_mangle]
pub extern "system" fn Java_com_edde746_plezy_browser_AdblockEngine_check(
    mut env: JNIEnv,
    _class: JClass,
    engine: jlong,
    url: JString,
    source: JString,
    kind: JString,
) -> jstring {
    let (Some(url), Some(source), Some(kind)) = (read(&mut env, &url), read(&mut env, &source), read(&mut env, &kind))
    else {
        return std::ptr::null_mut();
    };
    let mut redirect: *mut c_char = std::ptr::null_mut();
    let verdict = plezy_adblock_check(
        engine as *const PlezyAdblock,
        url.as_ptr(),
        source.as_ptr(),
        kind.as_ptr(),
        &mut redirect,
    );
    let redirect = take(redirect);
    match verdict {
        0 => std::ptr::null_mut(),
        2 => java(&mut env, Some(redirect.unwrap_or_default())),
        _ => java(&mut env, Some(String::new())),
    }
}

/// `{"script":string|null,"exceptions":"[...]","generichide":bool}`
#[no_mangle]
pub extern "system" fn Java_com_edde746_plezy_browser_AdblockEngine_pageScript(
    mut env: JNIEnv,
    _class: JClass,
    engine: jlong,
    url: JString,
) -> jstring {
    let Some(url) = read(&mut env, &url) else { return std::ptr::null_mut() };
    let mut exceptions: *mut c_char = std::ptr::null_mut();
    let mut generichide: c_int = 0;
    let script = take(plezy_adblock_page_script(
        engine as *const PlezyAdblock,
        url.as_ptr(),
        &mut exceptions,
        &mut generichide,
    ));
    let exceptions = take(exceptions).unwrap_or_else(|| "[]".into());
    let json = serde_json::json!({
        "script": script,
        "exceptions": exceptions,
        "generichide": generichide != 0,
    });
    java(&mut env, Some(json.to_string()))
}

#[no_mangle]
pub extern "system" fn Java_com_edde746_plezy_browser_AdblockEngine_genericScript(
    mut env: JNIEnv,
    _class: JClass,
    engine: jlong,
    query: JString,
    exceptions: JString,
) -> jstring {
    let (Some(query), Some(exceptions)) = (read(&mut env, &query), read(&mut env, &exceptions)) else {
        return std::ptr::null_mut();
    };
    let script = take(plezy_adblock_generic_script(
        engine as *const PlezyAdblock,
        query.as_ptr(),
        exceptions.as_ptr(),
    ));
    java(&mut env, script)
}
