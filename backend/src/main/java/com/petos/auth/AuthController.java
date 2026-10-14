package com.petos.auth;

import com.petos.common.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.context.SecurityContextRepository;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    public record Credentials(@NotBlank String loginName, @NotBlank String password) {}
    public record Registration(@NotBlank @Size(min = 3, max = 160) String loginName,
                               @NotBlank @Size(min = 10, max = 72) String password,
                               @NotBlank @Size(max = 120) String workspaceName) {}
    public record Identity(long id, String loginName, List<AuthMapper.Membership> workspaces) {}

    private final AuthMapper mapper;
    private final PasswordEncoder passwords;
    private final SecurityContextRepository repository;

    public AuthController(AuthMapper mapper, PasswordEncoder passwords,
                          SecurityContextRepository repository) {
        this.mapper = mapper;
        this.passwords = passwords;
        this.repository = repository;
    }

    @GetMapping("/csrf")
    public java.util.Map<String, String> csrf(CsrfToken token) {
        return java.util.Map.of("headerName", token.getHeaderName(), "token", token.getToken());
    }

    @PostMapping("/register")
    @Transactional
    public Identity register(@Valid @RequestBody Registration request,
                             HttpServletRequest servletRequest, HttpServletResponse servletResponse) {
        String loginName = request.loginName().trim();
        if (mapper.findByLogin(loginName) != null) {
            throw new ApiException(HttpStatus.CONFLICT, "账号已存在");
        }
        long userId = mapper.createAccount(loginName, passwords.encode(request.password()));
        long workspaceId = mapper.createWorkspace(request.workspaceName().trim());
        mapper.addOwner(workspaceId, userId);
        AppPrincipal principal = new AppPrincipal(userId, loginName);
        signIn(principal, servletRequest, servletResponse);
        return identity(principal);
    }

    @PostMapping("/login")
    public Identity login(@Valid @RequestBody Credentials request,
                          HttpServletRequest servletRequest, HttpServletResponse servletResponse) {
        AuthMapper.Account account = mapper.findByLogin(request.loginName().trim());
        if (account == null || !"ACTIVE".equals(account.status())
            || !passwords.matches(request.password(), account.passwordHash())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "账号或密码错误");
        }
        AppPrincipal principal = new AppPrincipal(account.id(), account.loginName());
        signIn(principal, servletRequest, servletResponse);
        return identity(principal);
    }

    @GetMapping("/me")
    public Identity me(Authentication authentication) {
        return identity((AppPrincipal) authentication.getPrincipal());
    }

    @PostMapping("/logout")
    public void logout(HttpServletRequest request) {
        SecurityContextHolder.clearContext();
        if (request.getSession(false) != null) {
            request.getSession(false).invalidate();
        }
    }

    private Identity identity(AppPrincipal principal) {
        return new Identity(principal.id(), principal.loginName(), mapper.memberships(principal.id()));
    }

    private void signIn(AppPrincipal principal, HttpServletRequest request,
                        HttpServletResponse response) {
        if (request.getSession(false) != null) {
            request.changeSessionId();
        }
        SecurityContext context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(new UsernamePasswordAuthenticationToken(principal, null, List.of()));
        SecurityContextHolder.setContext(context);
        repository.saveContext(context, request, response);
    }
}
