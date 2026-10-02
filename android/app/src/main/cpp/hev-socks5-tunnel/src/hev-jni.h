/*
 ============================================================================
 Name        : hev-jni.h
 Author      : hev <r@hev.cc>
 Copyright   : Copyright (c) 2019 - 2023 hev
 Description : Java Native Interface
 ============================================================================
 */

#ifndef __HEV_JNI_H__
#define __HEV_JNI_H__

#ifdef __ANDROID__
int hev_jni_protect_socket (int socket_fd);
#endif

#endif /* __HEV_JNI_H__ */
