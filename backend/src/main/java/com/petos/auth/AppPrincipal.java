package com.petos.auth;

import java.io.Serializable;

public record AppPrincipal(long id, String loginName) implements Serializable {}
