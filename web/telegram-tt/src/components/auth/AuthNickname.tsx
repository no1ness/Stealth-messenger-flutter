import {
  memo, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { GlobalState } from '../../global/types';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import InputText from '../ui/InputText';

type StateProps = {
  auth: GlobalState['auth'];
};

const AuthNickname = ({ auth }: StateProps) => {
  const { setAuthPhoneNumber } = getActions();
  const lang = useLang();

  const [nickname, setNickname] = useState('');
  const canSubmit = nickname.trim().length >= 2;

  const handleNicknameChange = useLastCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setNickname(e.target.value);
  });

  const handleSubmit = useLastCallback((e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!canSubmit || auth.isLoading) return;
    setAuthPhoneNumber({ phoneNumber: nickname.trim() });
  });

  return (
    <div id="auth-phone-number-form" className="custom-scroll">
      <div className="auth-form">
        <div id="logo" />
        <h1>{lang('AuthTitle')}</h1>
        <p className="note">Enter your nickname to get started</p>
        <form className="form" action="" onSubmit={handleSubmit}>
          <InputText
            id="sign-in-nickname"
            label="Your nickname"
            value={nickname}
            error={auth.errorKey && lang.withRegular(auth.errorKey)}
            inputMode="text"
            onChange={handleNicknameChange}
          />
          {canSubmit && (
            <Button
              className="auth-button"
              type="submit"
              ripple
              isLoading={auth.isLoading}
            >
              {lang('LoginNext')}
            </Button>
          )}
        </form>
      </div>
    </div>
  );
};

export default memo(withGlobal(
  (global): Complete<StateProps> => ({
    auth: global.auth,
  }),
)(AuthNickname));
