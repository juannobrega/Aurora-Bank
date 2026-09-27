#!/bin/bash
API=http://localhost:8080
ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; echo "     ${2:0:180}"; }

# Dois usuários distintos
for spec in "111.444.777-35|u1@t.test|11|11144477735" "529.982.247-25|u2@t.test|22|52998224725"; do
  IFS='|' read -r CPF MAIL SEED DIG <<< "$spec"
  U=$(curl -s -X POST $API/v1/onboarding/signup -H 'Content-Type: application/json' \
    -d "{\"fullName\":\"Pessoa Teste\",\"cpf\":\"$CPF\",\"email\":\"$MAIL\",\"pin\":\"2846\"}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  F=$(python3 -c "
import random; random.seed($SEED)
print('['+','.join('%.6f'%random.random() for _ in range(128))+']')")
  [ -n "$U" ] && curl -s -X POST $API/v1/onboarding/face -H 'Content-Type: application/json' \
    -d "{\"userId\":\"$U\",\"features\":$F,\"algorithm\":\"aurora-face-v1\",\"quality\":0.9,\"livenessPassed\":true}" >/dev/null
done

L1=$(curl -s -X POST $API/v1/auth/login/pin -H 'Content-Type: application/json' \
  -d '{"cpf":"11144477735","pin":"2846","device":{"hardwareId":"hwA","name":"iPhone A"}}')
T1=$(echo "$L1" | python3 -c "import json,sys; print(json.load(sys.stdin)['accessToken'])")
L2=$(curl -s -X POST $API/v1/auth/login/pin -H 'Content-Type: application/json' \
  -d '{"cpf":"52998224725","pin":"2846","device":{"hardwareId":"hwB","name":"iPhone B"}}')
T2=$(echo "$L2" | python3 -c "import json,sys; print(json.load(sys.stdin)['accessToken'])")
R2=$(echo "$L2" | python3 -c "import json,sys; print(json.load(sys.stdin)['refreshToken'])")

echo "=== IDOR: usuário 1 tenta revogar o aparelho do usuário 2 ==="
DEV2=$(curl -s $API/v1/auth/devices -H "Authorization: Bearer $T2" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
ATK=$(curl -s -X DELETE "$API/v1/auth/devices/$DEV2" -H "Authorization: Bearer $T1")
echo "$ATK" | grep -q DISPOSITIVO_NAO_RECONHECIDO && ok "não revoga aparelho alheio" || fail "IDOR ainda aberto!" "$ATK"

STILL=$(curl -s $API/v1/auth/devices -H "Authorization: Bearer $T2" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['status'])")
[ "$STILL" = "TRUSTED" ] && ok "aparelho da vítima segue ativo" || fail "aparelho foi revogado: $STILL" ""

echo "=== Autenticação fraca (refresh) não move dinheiro ==="
WEAK=$(curl -s -X POST $API/v1/auth/refresh -H 'Content-Type: application/json' \
  -d "{\"refreshToken\":\"$R2\"}" | python3 -c "import json,sys; print(json.load(sys.stdin)['accessToken'])")
P=$(curl -s -X POST $API/v1/pix/send -H "Authorization: Bearer $WEAK" -H 'Content-Type: application/json' \
  -d '{"pixKey":"alguem@email.com","amountCents":100}')
echo "$P" | grep -q AUTENTICACAO_FRACA && ok "Pix bloqueado com token BASIC" || fail "BASIC moveu dinheiro!" "$P"

B=$(curl -s $API/v1/account/balance -H "Authorization: Bearer $WEAK")
echo "$B" | grep -q amountCents && ok "mas consultar saldo funciona (leitura permitida)" || fail "leitura bloqueada" "$B"

echo "=== revoke-others preserva a sessão atual ==="
RV=$(curl -s -X POST $API/v1/auth/sessions/revoke-others -H "Authorization: Bearer $T2")
AFTER=$(curl -s -o /dev/null -w "%{http_code}" $API/v1/account/balance -H "Authorization: Bearer $T2")
[ "$AFTER" = "200" ] && ok "sessão atual sobrevive (revogou $(echo "$RV" | python3 -c "import json,sys; print(json.load(sys.stdin)['revoked'])" 2>/dev/null) outras)" || fail "derrubou a própria sessão: HTTP $AFTER" ""
