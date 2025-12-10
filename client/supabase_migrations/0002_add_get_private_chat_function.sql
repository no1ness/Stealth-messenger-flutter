CREATE OR REPLACE FUNCTION get_private_chat_with_user(user_id_param uuid)
RETURNS TABLE(chat_id uuid) AS $$
BEGIN
  RETURN QUERY
  SELECT cm1.chat_id
  FROM chat_members cm1
  JOIN chat_members cm2 ON cm1.chat_id = cm2.chat_id
  WHERE
    cm1.user_id = auth.uid() AND
    cm2.user_id = user_id_param AND
    (
      SELECT COUNT(*)
      FROM chat_members cm3
      WHERE cm3.chat_id = cm1.chat_id
    ) = 2;
END;
$$ LANGUAGE plpgsql;